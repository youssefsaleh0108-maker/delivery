package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
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

    @BeforeEach
    void setUp() {
        service = new StoreService(stores, offers, favorites, products, categories,
                Clock.fixed(Instant.parse("2026-08-27T12:00:00Z"), ZoneOffset.UTC));
        world.clear();

        // The stand-in for the PostGIS prefilter: it hands back every pinned shop and lets the
        // service do the narrowing it is responsible for. Testing the service against a database
        // that has already filtered by radius would test nothing about the radius.
        when(stores.findActiveIdsNear(anyDouble(), anyDouble(), anyDouble(), anyInt()))
                .thenAnswer(invocation -> List.copyOf(world.keySet()));

        when(stores.findAllById(any())).thenAnswer(invocation -> {
            List<Store> found = new ArrayList<>();
            for (UUID id : (Iterable<UUID>) invocation.getArgument(0)) {
                found.add(world.get(id));
            }
            return found;
        });
    }

    /** Registers a shop at a real place, and returns it so a test can name it in an assertion. */
    private Store shopAt(String name, double latitude, double longitude) {
        Store store = new Store("merchant-1", name, Store.Vertical.RESTAURANT);
        store.pinAt(GeoPoint.of(latitude, longitude));
        world.put(store.getId(), store);
        return store;
    }

    private Store shopWithNoPin(String name) {
        Store store = new Store("merchant-1", name, Store.Vertical.RESTAURANT);
        world.put(store.getId(), store);
        return store;
    }

    private List<String> namesNear(int radiusMetres) {
        Page<StoreService.NearbyStoreView> page =
                service.nearby(CUSTOMER, radiusMetres, 500, PageRequest.of(0, 20));
        return page.getContent().stream().map(n -> n.store().store().getName()).toList();
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
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 20)).getContent();

            assertThat(found).isSortedAccordingTo(
                    java.util.Comparator.comparingDouble(StoreService.NearbyStoreView::distanceMetres));
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
            moving.clearPin();

            assertThat(namesNear(10_000)).containsExactly("Downtown Grill");
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
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 2));
            Page<StoreService.NearbyStoreView> second =
                    service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(1, 2));

            assertThat(first.getContent()).extracting(n -> n.store().store().getName())
                    .containsExactly("Corner Cafe", "Downtown Grill");
            assertThat(second.getContent()).extracting(n -> n.store().store().getName())
                    .containsExactly("Achrafieh Bakery");
            assertThat(first.getTotalElements()).isEqualTo(3);
        }

        @Test
        void an_empty_result_is_an_empty_page_rather_than_a_failure() {
            assertThat(service.nearby(CUSTOMER, 10_000, 500, PageRequest.of(0, 20)))
                    .isEmpty();
        }
    }
}
