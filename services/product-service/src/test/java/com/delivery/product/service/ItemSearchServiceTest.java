package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.invocation.InvocationOnMock;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ItemSearchRepository;
import com.delivery.product.domain.ItemSearchRepository.Candidate;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.SearchRefusedException;
import com.delivery.product.service.ItemSearchService.ShopMatch;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * "Who near me sells Pepsi?" as the service decides it.
 *
 * <p>The database matches the words and narrows; this service judges every candidate again and decides
 * what a customer is shown, and in what order ({@link ItemSearchService}). These tests hold the second
 * half to account. The words themselves, the folding and the tiers are SQL, and
 * {@code ItemSearchDatabaseTest} checks them against a real PostgreSQL.
 *
 * <p>The coordinates are real places in Beirut, as in {@code NearbyStoreSearchTest}, so a failure is a
 * distance a reader can check on a map.
 */
@DisplayName("searching items across shops")
class ItemSearchServiceTest {

    /** Where the customer is standing: Hamra. */
    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);

    private static final Instant NOW = Instant.parse("2026-08-27T12:00:00Z");
    private static final Instant LONG_AGO = NOW.minus(Duration.ofDays(900));

    private static final int RADIUS = 5_000;
    private static final int CAP = 300;

    private final Map<UUID, Store> shops = new LinkedHashMap<>();
    private final Map<UUID, Product> products = new LinkedHashMap<>();

    /** A tier and score a test gives a product, in place of the stand-in's plain substring rule. */
    private final Map<UUID, Candidate> graded = new HashMap<>();

    private ItemSearchRepository search;
    private StoreRepository storeRepository;
    private ProductRepository productRepository;
    private StoreService storeService;

    /** What the service last asked the candidate query, argument by argument. */
    private Object[] asked;

    @BeforeEach
    void setUp() {
        shops.clear();
        products.clear();
        graded.clear();
        search = mock(ItemSearchRepository.class);
        storeRepository = mock(StoreRepository.class);
        productRepository = mock(ProductRepository.class);
        storeService = new StoreService(storeRepository, mock(StoreOfferRepository.class),
                mock(StoreFavoriteRepository.class), productRepository, mock(CategoryRepository.class),
                new ServiceCategories(new MockEnvironment()),
                mock(OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4));

        when(search.findCandidates(anyString(), anyString(), anyString(), anyString(), anyBoolean(),
                anyDouble(), anyDouble(), anyDouble(), anyDouble(), anyInt()))
                .thenAnswer(this::candidateQuery);
        when(productRepository.findAllById(any())).thenAnswer(call -> {
            List<Product> found = new ArrayList<>();
            for (UUID id : call.<Iterable<UUID>>getArgument(0)) {
                if (products.containsKey(id)) {
                    found.add(products.get(id));
                }
            }
            return found;
        });
        when(storeRepository.findAllById(any())).thenAnswer(call -> {
            List<Store> found = new ArrayList<>();
            for (UUID id : call.<Iterable<UUID>>getArgument(0)) {
                if (shops.containsKey(id)) {
                    found.add(shops.get(id));
                }
            }
            return found;
        });
    }

    /**
     * The stand-in for the SQL: faithful where the service relies on it, blind where it must not.
     *
     * <p>Faithful: a product matches when its name contains a term, ignoring case, or its barcode is the
     * barcode; the answer is best first (tier, score, product id) and stops at the LIMIT. A test can grade
     * a product with its own tier and score.
     *
     * <p>Blind: it hands back products of drafts, suspended shops, service shops and shops far away,
     * paused, draft and out-of-stock products, whatever the point. The service's own checks on those are
     * what these tests hold to account; a stand-in that had done them already would test nothing.
     */
    private List<Candidate> candidateQuery(InvocationOnMock call) {
        asked = call.getArguments();
        List<String> terms = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            String term = call.getArgument(i);
            if (!term.isEmpty()) {
                terms.add(term.toLowerCase());
            }
        }
        String barcode = call.getArgument(3);
        int maxRows = call.getArgument(9);
        List<Candidate> found = new ArrayList<>();
        for (Product product : products.values()) {
            Candidate grade = graded.get(product.getId());
            if (grade != null) {
                found.add(grade);
            } else if (!barcode.isEmpty() && barcode.equals(product.getBarcode())) {
                found.add(new Candidate(product.getId(), product.getStoreId(), 0, 0d));
            } else if (terms.stream().anyMatch(t -> product.getName().toLowerCase().contains(t))) {
                found.add(new Candidate(product.getId(), product.getStoreId(), 1, 1d));
            }
        }
        return found.stream()
                .sorted(Comparator.comparingInt(Candidate::tier)
                        .thenComparing(Candidate::score, Comparator.reverseOrder())
                        .thenComparing(Candidate::productId))
                .limit(maxRows)
                .toList();
    }

    // ------------------------------------------------------------------------------------ fixtures

    private ItemSearchService service() {
        return service(CAP);
    }

    private ItemSearchService service(int maxCandidates) {
        return new ItemSearchService(search, productRepository, storeRepository, storeService,
                Clock.fixed(NOW, ZoneOffset.UTC), RADIUS, maxCandidates);
    }

    /** A listed grocery, pinned, open all week. */
    private Store shopAt(String name, double latitude, double longitude) {
        Store store = new Store("merchant-" + name, name, Store.Vertical.GROCERY);
        store.pinAt(GeoPoint.of(latitude, longitude));
        store.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
        store.publish(LONG_AGO);
        shops.put(store.getId(), store);
        return store;
    }

    /** ~350 m north of the customer. */
    private Store corner(String name) {
        return shopAt(name, 33.900800d, 35.482900d);
    }

    /** ~1.7 km east, in Downtown. */
    private Store downtown(String name) {
        return shopAt(name, 33.895800d, 35.500900d);
    }

    /** ~4.6 km east, in Achrafieh. */
    private Store achrafieh(String name) {
        return shopAt(name, 33.888000d, 35.531000d);
    }

    private static List<StoreHours> everyDay(LocalTime opens, LocalTime closes) {
        List<StoreHours> week = new ArrayList<>();
        for (DayOfWeek day : DayOfWeek.values()) {
            week.add(new StoreHours(day, opens, closes));
        }
        return week;
    }

    /** A live, in-stock product on a shop's shelf. */
    private Product sells(Store shop, String name) {
        Product product = new Product(shop.getMerchantId(), shop.getId(), name, null,
                new BigDecimal("1.50"), null);
        product.addImage("products/" + UUID.randomUUID() + ".jpg");
        product.publish();
        products.put(product.getId(), product);
        return product;
    }

    /** {@link #sells}, with the tier and score the database would have given it. */
    private Product sells(Store shop, String name, int tier, double score) {
        Product product = sells(shop, name);
        graded.put(product.getId(), new Candidate(product.getId(), shop.getId(), tier, score));
        return product;
    }

    private ItemSearchResult searchNear(String q) {
        return service().search(ItemQuery.of(q, null, null), HAMRA, 0, 20);
    }

    private ItemSearchResult searchEverywhere(String q) {
        return service().search(ItemQuery.of(q, null, null), null, 0, 20);
    }

    private static List<String> shopNames(ItemSearchResult result) {
        return result.page().getContent().stream().map(m -> m.store().store().getName()).toList();
    }

    private static List<String> itemNames(ShopMatch match) {
        return match.items().stream().map(Product::getName).toList();
    }

    // ------------------------------------------------------------------------------------ the tests

    @Nested
    @DisplayName("what is never listed")
    class NeverListed {

        /**
         * A print shop's offer is a product row, and it may well be called Pepsi. It is never an item a
         * customer can have delivered, with a point or without one.
         */
        @Test
        void a_services_offer_is_never_returned_with_or_without_a_point() {
            Store press = new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING);
            press.pinAt(GeoPoint.of(33.898200d, 35.482500d));
            press.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
            press.publish(LONG_AGO);
            shops.put(press.getId(), press);
            sells(press, "Pepsi flyers, 500");
            sells(corner("Corner Grocer"), "Pepsi 1L");

            assertThat(shopNames(searchNear("pepsi"))).containsExactly("Corner Grocer");
            assertThat(shopNames(searchEverywhere("pepsi"))).containsExactly("Corner Grocer");
        }

        @Test
        void a_draft_or_suspended_shop_never_appears() {
            Store draft = new Store("merchant-draft", "Not Yet Open", Store.Vertical.GROCERY);
            draft.pinAt(GeoPoint.of(33.899000d, 35.483000d));
            draft.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
            shops.put(draft.getId(), draft);
            sells(draft, "Pepsi 1L");
            Store suspended = downtown("Suspended Grocer");
            suspended.suspend();
            sells(suspended, "Pepsi 1L");
            sells(achrafieh("Achrafieh Grocer"), "Pepsi 1L");

            assertThat(shopNames(searchNear("pepsi"))).containsExactly("Achrafieh Grocer");
            assertThat(shopNames(searchEverywhere("pepsi"))).containsExactly("Achrafieh Grocer");
        }

        @Test
        void a_paused_draft_or_out_of_stock_product_never_appears() {
            Store shop = corner("Corner Grocer");
            sells(shop, "Pepsi 1L").pause();
            Product draft = new Product(shop.getMerchantId(), shop.getId(), "Pepsi 2L", null,
                    new BigDecimal("2.00"), null);
            products.put(draft.getId(), draft);
            sells(shop, "Pepsi Max").applyStockProjection(false);
            sells(shop, "Pepsi Zero");

            ShopMatch match = searchNear("pepsi").page().getContent().get(0);
            assertThat(itemNames(match)).containsExactly("Pepsi Zero");
            assertThat(match.matchedInStore()).isEqualTo(1);
        }

        /**
         * Order Manager refuses a closed shop's order, so its items would be ones nobody can buy. A shop
         * behind on orders, or about to close, still takes one.
         */
        @Test
        void a_closed_shop_is_dropped_and_busy_and_closing_soon_stay() {
            Store shut = corner("Shut For The Day");
            shut.replaceHours(everyDay(LocalTime.of(6, 0), LocalTime.of(7, 0)));
            sells(shut, "Pepsi 1L");
            Store busy = downtown("Behind On Orders");
            busy.markBusyUntil(NOW.plusSeconds(1800));
            sells(busy, "Pepsi 1L");
            Store closing = achrafieh("Closing Soon");
            closing.replaceHours(everyDay(LocalTime.of(11, 0), LocalTime.of(12, 20)));
            sells(closing, "Pepsi 1L");

            ItemSearchResult result = searchNear("pepsi");

            assertThat(shopNames(result)).containsExactly("Behind On Orders", "Closing Soon");
            assertThat(result.page().getContent())
                    .extracting(m -> m.store().availability())
                    .containsExactly(Store.Availability.BUSY, Store.Availability.CLOSING_SOON);
        }

        /** Jounieh is some 17 km up the coast: not near a customer in Hamra. */
        @Test
        void a_shop_outside_the_radius_is_dropped_near_a_point_and_found_without_one() {
            sells(shopAt("Jounieh Grocer", 33.980800d, 35.617800d), "Pepsi 1L");
            sells(achrafieh("Achrafieh Grocer"), "Pepsi 1L");

            assertThat(shopNames(searchNear("pepsi"))).containsExactly("Achrafieh Grocer");
            assertThat(shopNames(searchEverywhere("pepsi")))
                    .containsExactlyInAnyOrder("Achrafieh Grocer", "Jounieh Grocer");
        }

        /** A shop that never dropped a pin has no distance, so it is not "near" anything. */
        @Test
        void a_shop_with_no_pin_is_found_only_without_a_point() {
            Store unpinned = new Store("merchant-nopin", "No Pin Grocer", Store.Vertical.GROCERY);
            unpinned.replaceHours(everyDay(LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)));
            unpinned.publish(LONG_AGO);
            shops.put(unpinned.getId(), unpinned);
            sells(unpinned, "Pepsi 1L");

            assertThat(searchNear("pepsi").page().getContent()).isEmpty();
            assertThat(shopNames(searchEverywhere("pepsi"))).containsExactly("No Pin Grocer");
        }

        /**
         * The shop said how far it carries. Downtown is ~1.7 km from the customer: a one-kilometre circle
         * does not reach them, a two-kilometre one does.
         */
        @Test
        void a_shop_whose_own_circle_does_not_reach_the_point_is_dropped() {
            Store small = downtown("Carries One Kilometre");
            small.setDeliveryRadiusMetres(1_000);
            sells(small, "Pepsi 1L");
            Store wide = shopAt("Carries Two Kilometres", 33.895800d, 35.501000d);
            wide.setDeliveryRadiusMetres(2_000);
            sells(wide, "Pepsi 1L");

            assertThat(shopNames(searchNear("pepsi"))).containsExactly("Carries Two Kilometres");
        }
    }

    @Nested
    @DisplayName("grouping and order")
    class GroupingAndOrder {

        /** The shop is what a customer orders from, so its matches travel together: the best three. */
        @Test
        void a_shops_matches_are_one_group_with_its_best_three_and_a_count_of_all() {
            Store shop = corner("Corner Grocer");
            sells(shop, "Pepsi Can", 1, 0.9d);
            sells(shop, "Diet Pepsi", 1, 0.8d);
            sells(shop, "Pepsi 1L", 1, 1.0d);
            sells(shop, "Pepsi Max", 3, 0.7d);
            sells(shop, "Pepsi Zero", 2, 1.0d);

            ItemSearchResult result = searchNear("pepsi");

            assertThat(result.page().getContent()).hasSize(1);
            ShopMatch match = result.page().getContent().get(0);
            assertThat(itemNames(match)).containsExactly("Pepsi 1L", "Pepsi Can", "Diet Pepsi");
            assertThat(match.matchedInStore()).isEqualTo(5);
            assertThat(result.page().getTotalElements()).isEqualTo(1);
        }

        /** Two equal matches in one shop are in id order, so a refresh does not swap them. */
        @Test
        void equal_matches_in_one_shop_are_in_product_id_order() {
            Store shop = corner("Corner Grocer");
            Product first = sells(shop, "Pepsi Can", 1, 1.0d);
            Product second = sells(shop, "Pepsi 1L", 1, 1.0d);
            List<String> byId = first.getId().compareTo(second.getId()) < 0
                    ? List.of("Pepsi Can", "Pepsi 1L")
                    : List.of("Pepsi 1L", "Pepsi Can");

            assertThat(itemNames(searchNear("pepsi").page().getContent().get(0))).isEqualTo(byId);
        }

        /**
         * The better match wins before distance: a shop that sells exactly "Pepsi" is listed above a
         * nearer one that only sells something that sounds like it. Then the better score, then the
         * nearer shop.
         */
        @Test
        void shops_are_ordered_by_best_tier_then_best_score_then_distance() {
            sells(corner("Near But Fuzzy"), "Pepsy", 3, 0.67d);
            sells(achrafieh("Far But Exact"), "Pepsi 1L", 1, 1.0d);
            sells(downtown("Middle Weaker Score"), "Pepsi Max", 1, 0.8d);
            sells(shopAt("Exact And Nearer", 33.896000d, 35.490000d), "Pepsi Can", 1, 1.0d);

            ItemSearchResult result = searchNear("pepsi");

            assertThat(shopNames(result)).containsExactly(
                    "Exact And Nearer", "Far But Exact", "Middle Weaker Score", "Near But Fuzzy");
            assertThat(result.nearby()).isTrue();
        }

        /** The distance is the sphere's, the same number "near me" puts on the card. */
        @Test
        void each_shop_carries_the_distance_that_ordered_it() {
            Store shop = downtown("Downtown Grocer");
            sells(shop, "Pepsi 1L");

            ShopMatch match = searchNear("pepsi").page().getContent().get(0);

            assertThat(match.distanceMetres())
                    .isCloseTo(HAMRA.distanceMetresTo(shop.location()), within(0.001d));
            assertThat(match.distanceMetres()).isBetween(1_600d, 1_800d);
        }

        /** Two shops at the same spot with equal matches: the id decides, every time. */
        @Test
        void a_tie_on_match_and_distance_is_broken_by_the_shop_id() {
            Store a = shopAt("Twin A", 33.899000d, 35.483000d);
            Store b = shopAt("Twin B", 33.899000d, 35.483000d);
            sells(a, "Pepsi 1L");
            sells(b, "Pepsi 1L");
            List<String> byId = a.getId().compareTo(b.getId()) < 0
                    ? List.of("Twin A", "Twin B")
                    : List.of("Twin B", "Twin A");

            assertThat(shopNames(searchNear("pepsi"))).isEqualTo(byId);
        }

        /**
         * With no point nothing is near, so after the match the better rated shop comes first, an unrated
         * one last, and no shop carries a distance.
         */
        @Test
        void without_a_point_equal_matches_are_ordered_by_rating_and_carry_no_distance() {
            Store unrated = corner("Unrated");
            sells(unrated, "Pepsi 1L");
            Store good = downtown("Good");
            good.applyRating(new BigDecimal("4.2"), 10);
            sells(good, "Pepsi 1L");
            Store best = achrafieh("Best");
            best.applyRating(new BigDecimal("4.9"), 30);
            sells(best, "Pepsi 1L");

            ItemSearchResult result = searchEverywhere("pepsi");

            assertThat(shopNames(result)).containsExactly("Best", "Good", "Unrated");
            assertThat(result.nearby()).isFalse();
            assertThat(result.page().getContent()).allMatch(m -> m.distanceMetres() == null);
        }

        @Test
        void the_groups_are_paged() {
            for (int i = 0; i < 5; i++) {
                sells(shopAt("Shop " + i, 33.8980d + i * 0.001d, 35.4830d), "Pepsi 1L");
            }

            ItemSearchResult second = service().search(ItemQuery.of("pepsi", null, null), HAMRA, 1, 2);

            assertThat(shopNames(second)).containsExactly("Shop 2", "Shop 3");
            assertThat(second.page().getTotalElements()).isEqualTo(5);
            assertThat(second.page().getTotalPages()).isEqualTo(3);
            assertThat(second.page().getNumber()).isEqualTo(1);
        }

        /** Asked for fifty, a page holds twenty; asked for none, it holds one; a negative page is the first. */
        @Test
        void the_page_size_is_clamped_and_a_negative_page_is_the_first() {
            for (int i = 0; i < 25; i++) {
                sells(shopAt("Shop " + i, 33.8980d + i * 0.0005d, 35.4830d), "Pepsi 1L");
            }
            ItemSearchService service = service();
            ItemQuery pepsi = ItemQuery.of("pepsi", null, null);

            assertThat(service.search(pepsi, HAMRA, 0, 50).page().getContent()).hasSize(20);
            assertThat(service.search(pepsi, HAMRA, 0, 0).page().getContent()).hasSize(1);
            assertThat(service.search(pepsi, HAMRA, -3, 5).page().getNumber()).isZero();
        }
    }

    @Nested
    @DisplayName("the ceiling on candidates")
    class Ceiling {

        /**
         * One row more than the ceiling is asked for, so an answer that reached it says so: the page
         * then covers the best matches only, and a client must not read an empty one as "nobody sells it".
         */
        @Test
        void an_answer_that_reached_the_ceiling_says_it_was_truncated() {
            Store shop = corner("Corner Grocer");
            for (int i = 0; i < 4; i++) {
                sells(shop, "Pepsi " + i);
            }

            ItemSearchResult capped = service(3).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);
            ItemSearchResult whole = service(4).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);

            assertThat(capped.truncated()).isTrue();
            assertThat(capped.candidateLimit()).isEqualTo(3);
            assertThat(capped.page().getContent().get(0).matchedInStore()).isEqualTo(3);
            assertThat(whole.truncated()).isFalse();
            assertThat(whole.page().getContent().get(0).matchedInStore()).isEqualTo(4);
        }

        /** Truncated means the best matches were kept: the weakest one is the one left out. */
        @Test
        void the_weakest_match_is_the_one_past_the_ceiling() {
            Store strong = corner("Strong");
            sells(strong, "Pepsi 1L", 1, 1.0d);
            Store weak = downtown("Weak");
            sells(weak, "Pepsy", 3, 0.6d);

            ItemSearchResult capped = service(1).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);

            assertThat(shopNames(capped)).containsExactly("Strong");
            assertThat(capped.truncated()).isTrue();
        }

        @Test
        void nothing_found_is_an_empty_page_that_is_not_truncated() {
            corner("Corner Grocer");

            ItemSearchResult result = searchNear("pepsi");

            assertThat(result.page().getContent()).isEmpty();
            assertThat(result.page().getTotalElements()).isZero();
            assertThat(result.truncated()).isFalse();
            assertThat(result.candidateLimit()).isEqualTo(CAP);
        }
    }

    @Nested
    @DisplayName("what the database is asked")
    class WhatTheDatabaseIsAsked {

        /**
         * The circle carries the same slack "near me" gives its own, so the spheroid cannot drop a shop
         * the sphere keeps; the sphere decides afterwards. One row more than the ceiling.
         */
        @Test
        void near_a_point_it_asks_for_the_widened_circle_and_one_row_past_the_ceiling() {
            searchNear("pepsi");

            assertThat(asked[4]).isEqualTo(true);
            assertThat((double) asked[5]).isEqualTo(33.8977d);
            assertThat((double) asked[6]).isEqualTo(35.4829d);
            assertThat((double) asked[7]).isEqualTo(RADIUS * StoreService.RADIUS_SLACK);
            assertThat((double) asked[8]).isEqualTo(StoreService.RADIUS_SLACK);
            assertThat(asked[9]).isEqualTo(CAP + 1);
        }

        @Test
        void without_a_point_it_asks_for_no_circle_and_binds_no_null() {
            searchEverywhere("pepsi");

            assertThat(asked[4]).isEqualTo(false);
            assertThat((double) asked[5]).isZero();
            assertThat((double) asked[6]).isZero();
        }

        /** q is the first slot, then the terms; an unused slot and an absent barcode are '' and never null. */
        @Test
        void q_and_the_terms_fill_the_slots_in_order() {
            service().search(ItemQuery.of("  pepsi  ", List.of("بيبسي"), null), HAMRA, 0, 10);
            assertThat(List.of(asked[0], asked[1], asked[2], asked[3]))
                    .containsExactly("pepsi", "بيبسي", "", "");

            service().search(ItemQuery.of(null, null, "5449000000996"), HAMRA, 0, 10);
            assertThat(List.of(asked[0], asked[1], asked[2], asked[3]))
                    .containsExactly("", "", "", "5449000000996");
        }

        /** The radius is the server's setting, held to "near me"'s bounds. */
        @Test
        void a_radius_setting_out_of_bounds_is_clamped() {
            new ItemSearchService(search, productRepository, storeRepository, storeService,
                    Clock.fixed(NOW, ZoneOffset.UTC), 900_000, CAP)
                    .search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10);

            assertThat((double) asked[7])
                    .isEqualTo(ItemSearchService.MAX_RADIUS_METRES * StoreService.RADIUS_SLACK);
        }
    }

    @Nested
    @DisplayName("what cannot be searched")
    class Refusals {

        private void refused(String code, Runnable search) {
            assertThatThrownBy(search::run)
                    .isInstanceOfSatisfying(SearchRefusedException.class,
                            e -> assertThat(e.getCode()).isEqualTo(code));
        }

        @Test
        void nothing_or_one_character_is_too_short() {
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of(null, null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("   ", null, "  "));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("p", null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of(" p ", null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("pepsi", List.of(""), null));
            assertThat(ItemQuery.of("pe", null, null).terms()).containsExactly("pe");
        }

        /** A reader counts an emoji as one character, and so does the limit. */
        @Test
        void more_than_a_hundred_characters_is_too_long() {
            refused(ItemSearchService.SEARCH_TOO_LONG, () -> ItemQuery.of("p".repeat(101), null, null));
            assertThat(ItemQuery.of("p".repeat(100), null, null).terms()).hasSize(1);
            String cup = new String(Character.toChars(0x1F964));
            assertThat(ItemQuery.of(cup.repeat(100), null, null).terms()).hasSize(1);
            refused(ItemSearchService.SEARCH_TOO_LONG, () -> ItemQuery.of(cup.repeat(101), null, null));
        }

        @Test
        void more_than_three_terms_counting_q_is_refused() {
            refused(ItemSearchService.SEARCH_TOO_MANY_TERMS,
                    () -> ItemQuery.of("pepsi", List.of("بيبسي", "pepsico", "cola"), null));
            assertThat(ItemQuery.of("pepsi", List.of("بيبسي", "pepsico"), null).terms()).hasSize(3);
        }

        @Test
        void a_barcode_is_eight_to_fourteen_digits() {
            refused(ItemSearchService.SEARCH_BAD_BARCODE, () -> ItemQuery.of(null, null, "1234567"));
            refused(ItemSearchService.SEARCH_BAD_BARCODE, () -> ItemQuery.of(null, null, "123456789012345"));
            refused(ItemSearchService.SEARCH_BAD_BARCODE, () -> ItemQuery.of(null, null, "54490000009X6"));
            assertThat(ItemQuery.of(null, null, " 12345678 ").barcode()).isEqualTo("12345678");
            assertThat(ItemQuery.of(null, null, "12345678901234").barcode()).isEqualTo("12345678901234");
        }

        /** The barcode is matched exactly and ranks first (tier 0), ahead of a nearer name match. */
        @Test
        void a_barcode_finds_its_product_first() {
            sells(corner("Corner Grocer"), "Pepsi Can");
            Product pepsi = sells(downtown("Downtown Grocer"), "Pepsi 1L");
            pepsi.assignCodes(null, "5449000000996");

            ItemSearchResult result = service().search(
                    ItemQuery.of("pepsi", null, "5449000000996"), HAMRA, 0, 10);

            assertThat(shopNames(result)).containsExactly("Downtown Grocer", "Corner Grocer");
        }
    }
}
