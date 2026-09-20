package com.delivery.product.service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.invocation.InvocationOnMock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.util.ReflectionTestUtils;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * "Shops near me".
 *
 * <p>The database narrows the candidates with PostGIS and this service decides the order and the
 * distance — see {@code StoreRepository#findActiveIdsNear} for why the work is split that way. The
 * consequence is that the half a customer actually sees, the ordering and the number on the card, is
 * the half these tests can hold to account.
 *
 * <p>The coordinates below are real junctions in Beirut, so a failure here is a distance a reader
 * can check on a map rather than an argument about arithmetic.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("shops near a point")
class NearbyStoreSearchTest {

    /** Where the customer is standing: Hamra, Beirut. */
    private static final GeoPoint CUSTOMER = GeoPoint.of(33.897700d, 35.482900d);

    /** The service's clock. */
    private static final Instant NOW = Instant.parse("2026-08-27T12:00:00Z");

    /** When a fixture listed unless a test says otherwise: long enough ago that it is not new. */
    private static final Instant LONG_AGO = NOW.minus(Duration.ofDays(900));

    /** How long a power declaration counts as now — the configured default. */
    private static final Duration FRESH_FOR = Duration.ofHours(4);

    @Mock
    private StoreRepository stores;
    @Mock
    private StoreOfferRepository offers;
    @Mock
    private StoreFavoriteRepository favorites;
    @Mock
    private ProductRepository products;
    @Mock
    private CategoryRepository categories;

    private StoreService service;
    private final Map<UUID, Store> world = new HashMap<>();

    /**
     * Runs after the candidate query and before the rows are read: the moment two queries leave
     * open, when a shop can change under the search.
     */
    private Runnable betweenTheQueries;

    /** The service's configuration, so a test can open or close a service category. */
    private org.springframework.mock.env.MockEnvironment environment;

    @BeforeEach
    void setUp() {
        environment = new org.springframework.mock.env.MockEnvironment();
        service = new StoreService(stores, offers, favorites, products, categories,
                new ServiceCategories(environment),
                org.mockito.Mockito.mock(OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), FRESH_FOR, "Asia/Beirut");
        world.clear();
        betweenTheQueries = () -> { };

        when(stores.findActiveIdsNear(anyDouble(), anyDouble(), anyDouble(), anyString(),
                any(Instant.class), anyString(), anyBoolean(), anyBoolean(), any(Instant.class),
                anyString(), anyString(), anyInt()))
                .thenAnswer(this::candidateQuery);

        when(stores.findAllById(any())).thenAnswer(invocation -> {
            betweenTheQueries.run();
            List<Store> found = new ArrayList<>();
            for (UUID id : (Iterable<UUID>) invocation.getArgument(0)) {
                found.add(world.get(id));
            }
            return found;
        });
    }

    /**
     * The stand-in for the PostGIS candidate query: faithful where the service relies on it, blind
     * where the service must not.
     *
     * <p>Faithful: a pin is required, the browse's filters are applied with exactly the arguments the
     * SQL binds and the same predicates, the answer is nearest first, and it stops at the LIMIT. The
     * stub used to ignore the LIMIT — which is how filters applied after the ceiling could lose a
     * matching shop while every test here stayed green.
     *
     * <p>Blind: it does not filter by radius or by status, and hands back drafts and suspended shops
     * too. The service's own checks on those are what the tests below hold to account; a stub that
     * had done them already would test nothing about them.
     */
    private List<UUID> candidateQuery(InvocationOnMock call) {
        GeoPoint centre = GeoPoint.of(call.<Double>getArgument(0), call.<Double>getArgument(1));
        String powerStatus = call.getArgument(3);
        Instant powerDeclaredSince = call.getArgument(4);
        String neighborhood = call.getArgument(5);
        boolean verifiedLocalOnly = call.getArgument(6);
        boolean newOnly = call.getArgument(7);
        Instant listedSince = call.getArgument(8);
        String vertical = call.getArgument(9);
        List<String> openCategories = List.of(call.<String>getArgument(10).split(","));
        int limit = call.getArgument(11);

        return world.values().stream()
                .filter(s -> s.location() != null)
                .filter(s -> vertical.isEmpty()
                        ? s.getVertical() != Store.Vertical.SERVICES
                        : s.getVertical().name().equals(vertical))
                .filter(s -> s.getVertical() != Store.Vertical.SERVICES
                        || openCategories.contains(s.getServiceCategory().name()))
                .filter(s -> powerStatus.isEmpty()
                        || (s.getPowerStatus().name().equals(powerStatus)
                                && s.getPowerUpdatedAt() != null
                                && !s.getPowerUpdatedAt().isBefore(powerDeclaredSince)))
                .filter(s -> neighborhood.isEmpty() || neighborhood.equals(s.getNeighborhood()))
                .filter(s -> !verifiedLocalOnly || s.isVerifiedLocal())
                .filter(s -> !newOnly
                        || (s.getPublishedAt() != null && !s.getPublishedAt().isBefore(listedSince)))
                .sorted(Comparator.comparingDouble((Store s) -> centre.distanceMetresTo(s.location())))
                .limit(limit)
                .map(Store::getId)
                .toList();
    }

    /**
     * Registers a listed, open shop at a real place, and returns it so a test can name it.
     *
     * <p>Published, with a whole week of all-day hours. These used to be left as constructed — DRAFT
     * — which the real candidate query never returns; the stub hands back whatever is in the world,
     * so the service has to be the thing that refuses a draft, and a fixture that is itself a draft
     * would be refused with it. It listed long ago, so it is not "new" unless a test says so.
     */
    private Store shopAt(String name, double latitude, double longitude) {
        return listedAt(name, latitude, longitude, LONG_AGO);
    }

    /** {@link #shopAt}, first listed at a chosen moment. */
    private Store listedAt(String name, double latitude, double longitude, Instant listed) {
        Store store = draftAt(name, latitude, longitude);
        store.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
        store.publish(listed);
        return store;
    }

    /** A shop created and pinned but never published — what every store is before it lists. */
    private Store draftAt(String name, double latitude, double longitude) {
        Store store = new Store("merchant-1", name, Store.Vertical.RESTAURANT);
        store.pinAt(GeoPoint.of(latitude, longitude));
        world.put(store.getId(), store);
        return store;
    }

    private static List<StoreHours> everyDay(LocalTime opens, LocalTime closes) {
        List<StoreHours> week = new ArrayList<>();
        for (DayOfWeek day : DayOfWeek.values()) {
            week.add(new StoreHours(day, opens, closes));
        }
        return week;
    }

    private Store shopWithNoPin(String name) {
        Store store = new Store("merchant-1", name, Store.Vertical.RESTAURANT);
        world.put(store.getId(), store);
        return store;
    }

    private static List<String> names(Page<StoreService.NearbyStoreView> page) {
        return page.getContent().stream().map(n -> n.store().store().getName()).toList();
    }

    private List<String> namesNear(int radiusMetres) {
        return names(service.nearby(CUSTOMER, radiusMetres, 500, PageRequest.of(0, 20)).page());
    }

    @Nested
    @DisplayName("ordering")
    class Ordering {

        /**
         * The assertion the whole feature turns on. Three shops at known distances from a known
         * point come back nearest first — not in insertion order, not in id order, and not in
         * whatever order the candidate query happened to return them.
         */
        @Test
        void lists_the_nearest_shop_first() {
            // ~1.7 km east, in Downtown.
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            // ~350 m north, still in Hamra.
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            // ~4.6 km east, in Achrafieh.
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);

            assertThat(namesNear(10_000))
                    .containsExactly("Corner Cafe", "Downtown Grill", "Achrafieh Bakery");
        }

        /** Fed in reverse, the answer must be identical — the order comes from the maths, not the input. */
        @Test
        void does_not_depend_on_the_order_the_candidates_arrived_in() {
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            shopAt("Corner Cafe", 33.900800d, 35.482900d);

            assertThat(namesNear(10_000))
                    .containsExactly("Corner Cafe", "Downtown Grill", "Achrafieh Bakery");
        }

        /**
         * The distance on the card is the distance that decided the order. If these ever came from
         * two different calculations, a customer would see a list whose second entry claims to be
         * closer than its first.
         */
        @Test
        void reports_a_distance_that_matches_the_order_it_produced() {
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            shopAt("Corner Cafe", 33.900800d, 35.482900d);

            List<StoreService.NearbyStoreView> found =
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 20)).page().getContent();

            assertThat(found).isSortedAccordingTo(
                    Comparator.comparingDouble(StoreService.NearbyStoreView::distanceMetres));
            assertThat(found.get(0).distanceMetres()).isCloseTo(345d,
                    org.assertj.core.data.Offset.offset(30d));
        }

        /** A shop in the same building as another must not swap places between refreshes. */
        @Test
        void breaks_a_tie_the_same_way_every_time() {
            shopAt("Ground Floor", 33.897700d, 35.482900d);
            shopAt("First Floor", 33.897700d, 35.482900d);

            assertThat(namesNear(10_000)).isEqualTo(namesNear(10_000));
        }
    }

    @Nested
    @DisplayName("the radius")
    class Radius {

        /**
         * The database is asked for slightly more than the radius, because the spheroid it filters
         * on and the sphere this service measures on disagree by about 0.3%. This service is what
         * decides, so anything past the radius has to be dropped here.
         */
        @Test
        void excludes_a_shop_past_it_even_though_the_database_offered_it() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);

            assertThat(namesNear(1_000)).containsExactly("Corner Cafe");
        }

        @Test
        void finds_nothing_when_the_nearest_shop_is_further_than_asked() {
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);

            assertThat(namesNear(500)).isEmpty();
        }
    }

    @Nested
    @DisplayName("shops that are not on the map")
    class Unpinned {

        /**
         * A merchant who has not dropped a pin has not told us where they are, and inventing a
         * position for them would put a shop on a customer's map at a place nobody chose. They keep
         * trading exactly as before — delivery is priced by area, not by metres — and are simply
         * absent from this one rail.
         */
        @Test
        void are_left_out_rather_than_given_a_default_position() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            shopWithNoPin("Phone Orders Only");

            assertThat(namesNear(10_000)).containsExactly("Corner Cafe");
        }

        @Test
        void a_pin_cleared_between_the_two_queries_does_not_break_the_search() {
            Store moving = shopAt("Corner Cafe", 33.900800d, 35.482900d);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            betweenTheQueries = moving::clearPin;

            assertThat(namesNear(10_000)).containsExactly("Downtown Grill");
        }
    }

    @Nested
    @DisplayName("shops that are not listed")
    class Unlisted {

        /**
         * The candidate query filters on ACTIVE, and the rows are then read again by id — so a shop
         * suspended between the two used to come back on the strength of the status it had a moment
         * earlier. The stub here returns every shop in the world, drafts included, which is exactly
         * the gap: the service must refuse them itself.
         */
        @Test
        void a_suspended_shop_never_appears() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            Store shut = shopAt("Downtown Grill", 33.895800d, 35.500900d);
            shut.suspend();

            assertThat(namesNear(10_000)).containsExactly("Corner Cafe");
        }

        @Test
        void a_draft_shop_never_appears() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            draftAt("Not Open Yet", 33.895800d, 35.500900d);

            assertThat(namesNear(10_000)).containsExactly("Corner Cafe");
        }
    }

    @Nested
    @DisplayName("the neighbourhood browse's filters")
    class Filters {

        private List<String> namesNear(StoreService.NearbyFilters filters) {
            return names(service.nearby(CUSTOMER, 10_000, 500, filters, PageRequest.of(0, 20)).page());
        }

        private static StoreService.NearbyFilters openNow() {
            return new StoreService.NearbyFilters(true, null, null, null, false);
        }

        private static StoreService.NearbyFilters power(Store.PowerStatus status) {
            return new StoreService.NearbyFilters(false, status, null, null, false);
        }

        private static StoreService.NearbyFilters district(String neighborhood) {
            return new StoreService.NearbyFilters(false, null, neighborhood, null, false);
        }

        private static StoreService.NearbyFilters newWithin(int days) {
            return new StoreService.NearbyFilters(false, null, null, days, false);
        }

        private static StoreService.NearbyFilters verifiedOnly() {
            return new StoreService.NearbyFilters(false, null, null, null, true);
        }

        /** A declaration made twenty minutes ago — comfortably current. */
        private static void declared(Store store, Store.PowerStatus status) {
            store.declarePower(status, null, NOW.minus(Duration.ofMinutes(20)));
        }

        @Test
        void no_filter_is_the_plain_search() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);

            assertThat(namesNear(StoreService.NearbyFilters.NONE))
                    .containsExactly("Corner Cafe", "Downtown Grill");
        }

        /**
         * "Open now" asks what a customer can buy from. A shop that is behind on orders, or about to
         * close, still takes an order; one outside its hours does not.
         */
        @Test
        void open_now_drops_a_closed_shop_and_keeps_busy_and_closing_soon() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            Store shut = shopAt("Shut For The Day", 33.899000d, 35.483000d);
            shut.replaceHours(everyDay(LocalTime.of(6, 0), LocalTime.of(7, 0)));
            Store busy = shopAt("Behind On Orders", 33.895800d, 35.500900d);
            busy.markBusyUntil(NOW.plusSeconds(1800));
            Store closing = shopAt("Closing Soon", 33.888000d, 35.531000d);
            closing.replaceHours(everyDay(LocalTime.of(11, 0), LocalTime.of(12, 20)));

            assertThat(namesNear(openNow()))
                    .containsExactly("Corner Cafe", "Behind On Orders", "Closing Soon");
        }

        /**
         * What the lights are doing now. A shop on mains is left out of a GENERATOR filter even
         * though it may well own one — which is why the client must not label this "has a
         * generator".
         */
        @Test
        void power_status_is_an_exact_match_on_what_was_declared() {
            declared(shopAt("On The Generator", 33.900800d, 35.482900d), Store.PowerStatus.GENERATOR);
            declared(shopAt("On Mains", 33.895800d, 35.500900d), Store.PowerStatus.MAINS);
            shopAt("Never Said", 33.888000d, 35.531000d);

            assertThat(namesNear(power(Store.PowerStatus.GENERATOR)))
                    .containsExactly("On The Generator");
        }

        /**
         * "On generator now" is a question about now. What a merchant said this morning is no answer
         * to it this evening — while a declaration exactly on the window's edge still is.
         */
        @Test
        void power_status_ignores_a_declaration_too_old_to_be_now() {
            Store recent = shopAt("Said An Hour Ago", 33.900800d, 35.482900d);
            recent.declarePower(Store.PowerStatus.GENERATOR, null, NOW.minus(Duration.ofHours(1)));
            Store edge = shopAt("Said Four Hours Ago", 33.899000d, 35.483000d);
            edge.declarePower(Store.PowerStatus.GENERATOR, null, NOW.minus(FRESH_FOR));
            Store stale = shopAt("Said This Morning", 33.895800d, 35.500900d);
            stale.declarePower(Store.PowerStatus.GENERATOR, null, NOW.minus(Duration.ofHours(9)));

            assertThat(namesNear(power(Store.PowerStatus.GENERATOR)))
                    .containsExactly("Said Four Hours Ago", "Said An Hour Ago");
        }

        /**
         * The card is told what the filter uses, so a "Generator active" badge is never drawn on a
         * shop the "on generator now" filter would leave out — nor on one that never said.
         */
        @Test
        void each_result_says_whether_its_declaration_still_counts_as_now() {
            Store recent = shopAt("Said An Hour Ago", 33.900800d, 35.482900d);
            recent.declarePower(Store.PowerStatus.DARK, null, NOW.minus(Duration.ofHours(1)));
            Store stale = shopAt("Said This Morning", 33.895800d, 35.500900d);
            stale.declarePower(Store.PowerStatus.DARK, null, NOW.minus(Duration.ofHours(9)));
            shopAt("Never Said", 33.888000d, 35.531000d);

            Map<String, Boolean> current = service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 20))
                    .page().getContent().stream()
                    .collect(Collectors.toMap(n -> n.store().store().getName(),
                            n -> n.store().powerCurrent()));

            assertThat(current).containsOnly(
                    Map.entry("Said An Hour Ago", true),
                    Map.entry("Said This Morning", false),
                    Map.entry("Never Said", false));
        }

        @Test
        void neighbourhood_is_an_exact_match_on_the_declared_district() {
            Store hamra = shopAt("Corner Cafe", 33.900800d, 35.482900d);
            hamra.setNeighborhood("Hamra");
            Store downtown = shopAt("Downtown Grill", 33.895800d, 35.500900d);
            downtown.setNeighborhood("Downtown");
            shopAt("No District", 33.888000d, 35.531000d);

            assertThat(namesNear(district("Hamra"))).containsExactly("Corner Cafe");
            // Trimmed on the way in, as the district is when it is stored.
            assertThat(namesNear(district("  Hamra "))).containsExactly("Corner Cafe");
            // Blank is no filter at all rather than "shops with a blank district".
            assertThat(namesNear(district("  ")))
                    .containsExactly("Corner Cafe", "Downtown Grill", "No District");
        }

        @Test
        void new_since_keeps_only_shops_that_listed_inside_the_window() {
            listedAt("Listed Last Week", 33.900800d, 35.482900d, NOW.minus(Duration.ofDays(7)));
            listedAt("Listed A Month Ago", 33.899000d, 35.483000d, NOW.minus(Duration.ofDays(30)));
            listedAt("Here For Years", 33.895800d, 35.500900d, NOW.minus(Duration.ofDays(900)));

            // Nearest first, as ever: the month-old shop is the closer of the two. The one exactly
            // on the window's edge is inside it.
            assertThat(namesNear(newWithin(30)))
                    .containsExactly("Listed A Month Ago", "Listed Last Week");
        }

        /**
         * "New" counts from the listing, not from the draft. A merchant who spent four months
         * setting up and listed last week has just joined; one suspended and listed again two days
         * ago has not. Both used to be judged by the draft row's creation time.
         */
        @Test
        void new_since_reads_the_first_listing_not_the_draft() {
            Store slowStart = listedAt("Set Up For Months", 33.900800d, 35.482900d,
                    NOW.minus(Duration.ofDays(7)));
            ReflectionTestUtils.setField(slowStart, "createdAt", NOW.minus(Duration.ofDays(120)));
            Store relisted = listedAt("Back After A Suspension", 33.899000d, 35.483000d,
                    NOW.minus(Duration.ofDays(400)));
            ReflectionTestUtils.setField(relisted, "createdAt", NOW.minus(Duration.ofDays(401)));
            relisted.suspend();
            relisted.publish(NOW.minus(Duration.ofDays(2)));

            assertThat(namesNear(newWithin(30))).containsExactly("Set Up For Months");
        }

        /** "New" is a claim made on the card. A shop with no listing time on record is not new. */
        @Test
        void a_shop_with_no_listing_time_is_not_new() {
            Store unknown = shopAt("Unknown Age", 33.900800d, 35.482900d);
            ReflectionTestUtils.setField(unknown, "publishedAt", null);

            assertThat(namesNear(newWithin(365))).isEmpty();
        }

        @Test
        void verified_local_keeps_only_shops_backoffice_vouched_for() {
            Store vouched = shopAt("Abu Hassan", 33.900800d, 35.482900d);
            vouched.setVerifiedLocal(true);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);

            assertThat(namesNear(verifiedOnly())).containsExactly("Abu Hassan");
        }

        /** Filters narrow the radius's answer; they never widen it. */
        @Test
        void filters_combine_with_the_radius_and_with_each_other() {
            declared(shopAt("Corner Cafe", 33.900800d, 35.482900d), Store.PowerStatus.GENERATOR);
            declared(shopAt("Achrafieh Bakery", 33.888000d, 35.531000d), Store.PowerStatus.GENERATOR);
            Store nearButShut = shopAt("Shut Generator Shop", 33.899000d, 35.483000d);
            declared(nearButShut, Store.PowerStatus.GENERATOR);
            nearButShut.replaceHours(everyDay(LocalTime.of(6, 0), LocalTime.of(7, 0)));

            List<String> found = names(service.nearby(CUSTOMER, 1_000, 500,
                            new StoreService.NearbyFilters(true, Store.PowerStatus.GENERATOR,
                                    null, null, false),
                            PageRequest.of(0, 20))
                    .page());

            assertThat(found).containsExactly("Corner Cafe");
        }

        /**
         * The rows are judged again as they are read. A shop that went back to mains between the
         * candidate query and the row read is not handed to "on generator now" on the strength of
         * what it said a moment earlier.
         */
        @Test
        void a_shop_that_stopped_matching_between_the_two_queries_is_left_out() {
            Store switching = shopAt("Back On Mains", 33.900800d, 35.482900d);
            declared(switching, Store.PowerStatus.GENERATOR);
            declared(shopAt("Still On The Generator", 33.895800d, 35.500900d),
                    Store.PowerStatus.GENERATOR);
            betweenTheQueries = () -> switching.declarePower(Store.PowerStatus.MAINS, null, NOW);

            assertThat(namesNear(power(Store.PowerStatus.GENERATOR)))
                    .containsExactly("Still On The Generator");
        }

        /**
         * The page is cut after filtering. Filtering a page after it was cut — what the client used
         * to have to do — returns short pages and a total that counts shops the customer will never
         * see.
         */
        @Test
        void pages_and_totals_count_only_what_the_filter_let_through() {
            for (int i = 0; i < 3; i++) {
                declared(shopAt("Generator " + i, 33.8977d + i * 0.001d, 35.4829d),
                        Store.PowerStatus.GENERATOR);
                shopAt("Mains " + i, 33.8977d + i * 0.001d + 0.0005d, 35.4829d);
            }

            Page<StoreService.NearbyStoreView> first = service.nearby(CUSTOMER, 10_000, 500,
                    power(Store.PowerStatus.GENERATOR), PageRequest.of(0, 2)).page();

            assertThat(first.getContent()).hasSize(2);
            assertThat(first.getTotalElements()).isEqualTo(3);
            assertThat(first.getContent()).allSatisfy(n -> assertThat(
                    n.store().store().getPowerStatus()).isEqualTo(Store.PowerStatus.GENERATOR));
        }
    }

    @Nested
    @DisplayName("the candidate ceiling")
    class Ceiling {

        /**
         * Why the filters are in the query. 520 live shops inside two kilometres, and the only one on
         * its generator is the 510th nearest. With the filters applied only after the ceiling, the
         * nearest 500 were read, none matched, and the customer was told no shop did.
         */
        @Test
        void filters_narrow_the_candidates_before_the_ceiling_rather_than_after() {
            for (int i = 0; i < 520; i++) {
                Store shop = shopAt("Shop " + i, 33.8977d + (i + 1) * 0.00001d, 35.4829d);
                if (i == 509) {
                    shop.declarePower(Store.PowerStatus.GENERATOR, null,
                            NOW.minus(Duration.ofMinutes(5)));
                }
            }

            StoreService.NearbyResult found = service.nearby(CUSTOMER, 2_000, 500,
                    new StoreService.NearbyFilters(false, Store.PowerStatus.GENERATOR, null, null,
                            false),
                    PageRequest.of(0, 20));

            assertThat(names(found.page())).containsExactly("Shop 509");
            assertThat(found.page().getTotalElements()).isEqualTo(1);
            assertThat(found.truncated()).isFalse();
        }

        /**
         * Past the ceiling the answer is about the nearest shops only, and it says so. Exactly as many
         * shops as the ceiling is not past it: the query asks for one more than it will use, so "there
         * were more" is seen rather than guessed.
         */
        @Test
        void a_search_that_reaches_the_ceiling_keeps_the_nearest_and_says_so() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);

            StoreService.NearbyResult capped =
                    service.nearby(CUSTOMER, 10_000, 2, PageRequest.of(0, 20));
            assertThat(capped.truncated()).isTrue();
            assertThat(names(capped.page())).containsExactly("Corner Cafe", "Downtown Grill");
            assertThat(capped.page().getTotalElements()).isEqualTo(2);

            StoreService.NearbyResult exact =
                    service.nearby(CUSTOMER, 10_000, 3, PageRequest.of(0, 20));
            assertThat(exact.truncated()).isFalse();
            assertThat(names(exact.page())).hasSize(3);
        }
    }

    @Nested
    @DisplayName("paging")
    class Paging {

        @Test
        void cuts_the_page_after_ordering_rather_than_before() {
            shopAt("Achrafieh Bakery", 33.888000d, 35.531000d);
            shopAt("Downtown Grill", 33.895800d, 35.500900d);
            shopAt("Corner Cafe", 33.900800d, 35.482900d);

            Page<StoreService.NearbyStoreView> first =
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 2)).page();
            Page<StoreService.NearbyStoreView> second =
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(1, 2)).page();

            assertThat(first.getContent()).extracting(n -> n.store().store().getName())
                    .containsExactly("Corner Cafe", "Downtown Grill");
            assertThat(second.getContent()).extracting(n -> n.store().store().getName())
                    .containsExactly("Achrafieh Bakery");
            assertThat(first.getTotalElements()).isEqualTo(3);
        }

        @Test
        void an_empty_result_is_an_empty_page_rather_than_a_failure() {
            StoreService.NearbyResult nothing =
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 20));

            assertThat(nothing.page()).isEmpty();
            assertThat(nothing.truncated()).isFalse();
        }
    }

    /**
     * Service shops in "near me". The plain search is what the neighbourhood browse and every
     * installed app make, and those apps read an unknown vertical as a restaurant — so a print shop
     * round the corner must not be in that answer. The stand-in candidate query applies the vertical
     * and category exactly as the SQL does, which is what makes these tests of the service's
     * arguments rather than of the stub.
     */
    @Nested
    @DisplayName("service shops")
    class ServiceShops {

        private Store serviceShopAt(String name, Store.ServiceCategory category, double latitude,
                                    double longitude) {
            Store store = new Store("merchant-2", name, Store.Vertical.SERVICES, category);
            store.pinAt(GeoPoint.of(latitude, longitude));
            store.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
            store.publish(LONG_AGO);
            world.put(store.getId(), store);
            return store;
        }

        private List<String> namesNear(StoreService.NearbyFilters filters) {
            return names(service.nearby(CUSTOMER, 10_000, 500, filters, PageRequest.of(0, 20))
                    .page());
        }

        private StoreService.NearbyFilters asking(Store.Vertical vertical,
                                                  Store.ServiceCategory category) {
            return new StoreService.NearbyFilters(false, null, null, null, false, vertical, category);
        }

        @Test
        void the_plain_search_leaves_service_shops_out() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            serviceShopAt("Al Fakhry Press", Store.ServiceCategory.PRINTING, 33.898000d, 35.483000d);

            assertThat(namesNear(StoreService.NearbyFilters.NONE)).containsExactly("Corner Cafe");
        }

        @Test
        void asking_for_services_lists_service_shops_in_open_categories_only() {
            shopAt("Corner Cafe", 33.900800d, 35.482900d);
            serviceShopAt("Al Fakhry Press", Store.ServiceCategory.PRINTING, 33.898000d, 35.483000d);
            serviceShopAt("Spotless Cleaners", Store.ServiceCategory.CLEANING, 33.899000d, 35.484000d);

            assertThat(namesNear(asking(Store.Vertical.SERVICES, null)))
                    .containsExactly("Al Fakhry Press");
        }

        @Test
        void a_category_narrows_to_that_category() {
            serviceShopAt("Al Fakhry Press", Store.ServiceCategory.PRINTING, 33.898000d, 35.483000d);
            serviceShopAt("Hamra Tailors", Store.ServiceCategory.TAILORING, 33.899000d, 35.484000d);

            assertThat(namesNear(asking(null, Store.ServiceCategory.TAILORING)))
                    .containsExactly("Hamra Tailors");
        }

        @Test
        void a_closed_category_answers_nothing_without_asking_the_database() {
            serviceShopAt("Spotless Cleaners", Store.ServiceCategory.CLEANING, 33.899000d, 35.484000d);

            StoreService.NearbyResult result = service.nearby(CUSTOMER, 10_000, 500,
                    asking(Store.Vertical.SERVICES, Store.ServiceCategory.CLEANING),
                    PageRequest.of(0, 20));

            assertThat(result.page()).isEmpty();
            org.mockito.Mockito.verify(stores, org.mockito.Mockito.never()).findActiveIdsNear(
                    anyDouble(), anyDouble(), anyDouble(), anyString(), any(Instant.class),
                    anyString(), anyBoolean(), anyBoolean(), any(Instant.class), anyString(),
                    anyString(), anyInt());
        }

        @Test
        void opening_a_category_lists_its_shops() {
            environment.setProperty("delivery.product.services.enabled-categories",
                    "PRINTING,CLEANING");
            serviceShopAt("Spotless Cleaners", Store.ServiceCategory.CLEANING, 33.899000d, 35.484000d);

            assertThat(namesNear(asking(Store.Vertical.SERVICES, null)))
                    .containsExactly("Spotless Cleaners");
        }

        /**
         * The ids and the rows come from two queries. A shop re-filed under another category in
         * between is judged on what it is now, the same rule every other filter follows.
         */
        @Test
        void a_shop_refiled_between_the_two_queries_is_judged_on_what_it_is_now() {
            Store press = serviceShopAt("Al Fakhry Press", Store.ServiceCategory.PRINTING,
                    33.898000d, 35.483000d);
            betweenTheQueries = () -> press.changeServiceCategory(Store.ServiceCategory.PHOTOGRAPHY);

            assertThat(namesNear(asking(null, Store.ServiceCategory.PRINTING))).isEmpty();
        }

        @Test
        void the_browse_filters_still_narrow_service_shops() {
            Store press = serviceShopAt("Al Fakhry Press", Store.ServiceCategory.PRINTING,
                    33.898000d, 35.483000d);
            press.setVerifiedLocal(true);
            serviceShopAt("Unvetted Prints", Store.ServiceCategory.PRINTING, 33.899000d, 35.484000d);

            assertThat(namesNear(new StoreService.NearbyFilters(false, null, null, null, true,
                    Store.Vertical.SERVICES, null)))
                    .containsExactly("Al Fakhry Press");
        }
    }
}
