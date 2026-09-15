package com.delivery.product.service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.Store.ServiceCategory;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.StoreService.NearbyStoreView;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The Services tab's "Popular near you" row: what is asked of the database, and what is done with the
 * answer.
 *
 * <p>The ranking itself (distinct orders inside the window, the floor, the circle, the scope, ties by
 * rating) is SQL, and is proven against PostGIS in {@code ServiceOffersDatabaseTest}. This pins the
 * question the service asks, that the database's order is the order that ships, and that every row is
 * judged again as it is read. No count is in anything this returns, because none is ever read.
 *
 * <p>The customer stands in Hamra, Beirut, and every shop is due north of them, so each distance is a
 * number of kilometres a reader can check on a map.
 */
@DisplayName("popular service shops near the customer")
class PopularServiceShopsTest {

    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);
    private static final Instant NOW = Instant.parse("2026-09-14T10:00:00Z");
    private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

    /** One kilometre of latitude in degrees, on the sphere the service measures on. */
    private static final double KILOMETRE = 1 / 111.195d;

    private StoreRepository stores;
    private StoreService storeService;
    private MockEnvironment environment;

    /** The stand-in ranked query's answer, most delivered first. */
    private final List<UUID> ranking = new ArrayList<>();
    private final Map<UUID, Store> world = new HashMap<>();

    @BeforeEach
    void setUp() {
        stores = mock(StoreRepository.class);
        environment = new MockEnvironment();
        storeService = new StoreService(stores, mock(StoreOfferRepository.class),
                mock(StoreFavoriteRepository.class), mock(ProductRepository.class),
                mock(CategoryRepository.class), new ServiceCategories(environment),
                mock(OnboardingApplicationClient.class), Clock.fixed(NOW, ZoneOffset.UTC),
                Duration.ofHours(4));

        when(stores.findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(), anyString(),
                any(Instant.class), anyLong(), anyInt()))
                .thenAnswer(call -> List.copyOf(
                        ranking.subList(0, Math.min(ranking.size(), call.<Integer>getArgument(6)))));
        // Like the real findAllById, in no promised order: here, the reverse of the ranking.
        when(stores.findAllById(any())).thenAnswer(call -> {
            List<Store> found = new ArrayList<>();
            call.<Iterable<UUID>>getArgument(0).forEach(id -> found.add(world.get(id)));
            Collections.reverse(found);
            return found;
        });
    }

    private PopularServiceShops popular() {
        return popular(5000, 30, 3);
    }

    private PopularServiceShops popular(int radiusMetres, int windowDays, long minDeliveredOrders) {
        return new PopularServiceShops(stores, storeService, new ServiceCategories(environment),
                Clock.fixed(NOW, ZoneOffset.UTC), radiusMetres, windowDays, minDeliveredOrders);
    }

    /** A listed service shop {@code kilometres} due north of the customer, ranked below those before it. */
    private Store ranked(String name, ServiceCategory category, double kilometres) {
        Store shop = new Store("merchant-" + UUID.randomUUID(), name, Store.Vertical.SERVICES, category);
        shop.pinAt(GeoPoint.of(33.897700d + kilometres * KILOMETRE, 35.482900d));
        shop.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        shop.publish(NOW.minus(Duration.ofDays(90)));
        world.put(shop.getId(), shop);
        ranking.add(shop.getId());
        return shop;
    }

    private static List<String> names(List<NearbyStoreView> row) {
        return row.stream().map(near -> near.store().store().getName()).toList();
    }

    @Test
    void asks_for_the_customers_circle_the_open_categories_the_last_thirty_days_and_the_floor() {
        popular().near(HAMRA, null, 10);

        verify(stores).findPopularServiceShopIdsNear(eq(33.8977d), eq(35.4829d),
                eq(5000 * StoreService.RADIUS_SLACK), eq("PHOTOGRAPHY,PRINTING,REPAIRS,TAILORING"),
                eq(NOW.minus(Duration.ofDays(30))), eq(3L), eq(10));
    }

    /** Only the database knows the counts, so its order is the one that ships, not nearest first. */
    @Test
    void keeps_the_databases_ranking_and_measures_each_card() {
        ranked("Busy Tailor", ServiceCategory.TAILORING, 3.0);
        ranked("Quiet Printer", ServiceCategory.PRINTING, 1.0);

        List<NearbyStoreView> row = popular().near(HAMRA, null, 10);

        assertThat(names(row)).containsExactly("Busy Tailor", "Quiet Printer");
        assertThat(row.get(0).distanceMetres()).isCloseTo(3000d, within(5d));
        assertThat(row.get(1).distanceMetres()).isCloseTo(1000d, within(5d));
    }

    @Test
    void a_shop_the_radius_slack_let_in_but_outside_the_circle_is_dropped() {
        ranked("Just Outside", ServiceCategory.PRINTING, 5.02);
        ranked("Just Inside", ServiceCategory.PRINTING, 4.98);

        assertThat(names(popular().near(HAMRA, null, 10))).containsExactly("Just Inside");
    }

    /** The ids and the rows come from two queries, and a shop is judged on what it is by the second. */
    @Test
    void a_shop_suspended_unpinned_or_in_a_closed_category_by_the_time_it_is_read_is_dropped() {
        ranked("Suspended Press", ServiceCategory.PRINTING, 1.0).suspend();
        ranked("Unpinned Repairs", ServiceCategory.REPAIRS, 1.0).clearPin();
        ranked("Spotless Cleaners", ServiceCategory.CLEANING, 1.0);
        ranked("Listed Photos", ServiceCategory.PHOTOGRAPHY, 1.0);

        assertThat(names(popular().near(HAMRA, null, 10))).containsExactly("Listed Photos");
    }

    @Test
    void an_open_category_named_is_the_only_one_ranked() {
        popular().near(HAMRA, ServiceCategory.PRINTING, 10);

        verify(stores).findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(),
                eq("PRINTING"), any(Instant.class), anyLong(), anyInt());
    }

    @Test
    void a_closed_category_named_is_empty_without_asking_the_database() {
        assertThat(popular().near(HAMRA, ServiceCategory.BEAUTY, 10)).isEmpty();

        verify(stores, never()).findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(),
                anyString(), any(Instant.class), anyLong(), anyInt());
    }

    @Test
    void a_category_opened_in_configuration_is_ranked_with_the_others() {
        environment.setProperty(OPEN_CATEGORIES, "PRINTING,CLEANING");

        popular().near(HAMRA, null, 10);

        verify(stores).findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(),
                eq("CLEANING,PRINTING"), any(Instant.class), anyLong(), anyInt());
    }

    @Test
    void nothing_ranked_reads_no_shop() {
        assertThat(popular().near(HAMRA, null, 10)).isEmpty();

        verify(stores, never()).findAllById(any());
    }

    /**
     * A setting can neither make the row nationwide nor call a shop popular on nobody's orders: the
     * radius is held to "near me"'s widest circle, and the window and the floor to at least one.
     */
    @Test
    void settings_cannot_make_the_row_nationwide_or_popular_on_nobodys_orders() {
        popular(1_000_000, 0, 0).near(HAMRA, null, 10);

        verify(stores).findPopularServiceShopIdsNear(anyDouble(), anyDouble(),
                eq(PopularServiceShops.MAX_RADIUS_METRES * StoreService.RADIUS_SLACK), anyString(),
                eq(NOW.minus(Duration.ofDays(1))), eq(1L), anyInt());
    }

    @Test
    void a_request_for_a_long_row_is_bounded_and_one_for_none_still_asks_for_one() {
        PopularServiceShops popular = popular();

        popular.near(HAMRA, null, 500);
        popular.near(HAMRA, null, 0);

        verify(stores).findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(), anyString(),
                any(Instant.class), anyLong(), eq(PopularServiceShops.MAX_SHOPS));
        verify(stores).findPopularServiceShopIdsNear(anyDouble(), anyDouble(), anyDouble(), anyString(),
                any(Instant.class), anyLong(), eq(1));
    }
}
