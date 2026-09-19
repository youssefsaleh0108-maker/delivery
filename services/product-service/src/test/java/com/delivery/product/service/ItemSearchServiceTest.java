package com.delivery.product.service;

import java.math.BigDecimal;
import java.sql.SQLException;
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
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.invocation.InvocationOnMock;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.QueryTimeoutException;
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
import com.delivery.product.service.ItemSearchService.SearchTimedOutException;
import com.delivery.product.service.ItemSearchService.ShopMatch;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * "Who near me sells Pepsi?" as the service decides it.
 *
 * <p>The database matches the words, narrows, caps each shop and counts; this service checks the words
 * it is asked for, bounds the database's time, judges every candidate again and decides what a customer
 * is shown, and in what order ({@link ItemSearchService}). These tests hold the service to account. The
 * words themselves, the folding, the tiers, the caps and the order the cut keeps are SQL, and
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
    private static final Duration TIMEOUT = Duration.ofSeconds(2);

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
        asked = null;
        search = mock(ItemSearchRepository.class);
        storeRepository = mock(StoreRepository.class);
        productRepository = mock(ProductRepository.class);
        storeService = new StoreService(storeRepository, mock(StoreOfferRepository.class),
                mock(StoreFavoriteRepository.class), productRepository, mock(CategoryRepository.class),
                new ServiceCategories(new MockEnvironment()),
                mock(OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4));

        when(search.findCandidates(anyString(), anyString(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyBoolean(), anyDouble(), anyDouble(), anyDouble(), anyDouble(),
                any(), anyInt(), anyInt()))
                .thenAnswer(this::candidateQuery);
        when(productRepository.foldForSearch(anyString(), anyString(), anyString()))
                .thenAnswer(call -> List.of(fold(call.getArgument(0)), fold(call.getArgument(1)),
                        fold(call.getArgument(2))));
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
     * The stand-in for {@code search_fold}: enough of it for these tests' Latin and Arabic words. The
     * real one is V37's, and {@code ItemSearchDatabaseTest} checks it.
     */
    private static String fold(String term) {
        return term.toLowerCase(Locale.ROOT)
                .replaceAll("['’]", "")
                .replaceAll("[^a-z0-9\\u0621-\\u064A]+", " ")
                .strip();
    }

    /**
     * The stand-in for the SQL: faithful where the service relies on it, blind where it must not.
     *
     * <p>Faithful: a product matches when its folded name contains a folded phrase, or its barcode is
     * the barcode; each shop keeps its best {@code perStore} matches (tier, score, product id) and says
     * how many it had; the rows are ordered as the query orders them (tier, score, the nearer shop on
     * the sphere, the better rating, the ids) and stop at the LIMIT. A test can grade a product with its
     * own tier and score.
     *
     * <p>Blind: it hands back products of drafts, suspended shops, service shops, closed shops and shops
     * far away, paused, draft and out-of-stock products, whatever the point. The service's own checks on
     * those are what these tests hold to account; a stand-in that had done them already would test
     * nothing.
     */
    private List<Candidate> candidateQuery(InvocationOnMock call) {
        asked = call.getArguments();
        List<String> phrases = new ArrayList<>();
        for (int slot : new int[] {0, 2, 4}) {
            String phrase = call.getArgument(slot);
            if (!phrase.isEmpty()) {
                phrases.add(phrase);
            }
        }
        String barcode = call.getArgument(6);
        boolean near = call.getArgument(7);
        GeoPoint point = near ? GeoPoint.of(call.<Double>getArgument(8), call.<Double>getArgument(9)) : null;
        int perStore = call.getArgument(13);
        int maxRows = call.getArgument(14);

        Map<UUID, List<Candidate>> byShop = new LinkedHashMap<>();
        for (Product product : products.values()) {
            Candidate match = graded.get(product.getId());
            if (match == null && !barcode.isEmpty() && barcode.equals(product.getBarcode())) {
                match = new Candidate(product.getId(), product.getStoreId(), 0, 0d, 0);
            } else if (match == null && phrases.stream().anyMatch(p -> fold(product.getName()).contains(p))) {
                match = new Candidate(product.getId(), product.getStoreId(), 1, 1d, 0);
            }
            if (match != null) {
                byShop.computeIfAbsent(match.storeId(), id -> new ArrayList<>()).add(match);
            }
        }
        Comparator<Candidate> bestFirst = Comparator.comparingInt(Candidate::tier)
                .thenComparing(Candidate::score, Comparator.reverseOrder())
                .thenComparing(Candidate::productId);
        List<Candidate> rows = new ArrayList<>();
        byShop.forEach((storeId, matches) -> matches.stream().sorted(bestFirst).limit(perStore)
                .map(c -> new Candidate(c.productId(), c.storeId(), c.tier(), c.score(), matches.size()))
                .forEach(rows::add));
        rows.sort(Comparator.comparingInt(Candidate::tier)
                .thenComparing(Candidate::score, Comparator.reverseOrder())
                .thenComparingDouble(c -> distanceTo(point, c.storeId()))
                .thenComparing(c -> shops.containsKey(c.storeId()) ? shops.get(c.storeId()).getRating() : null,
                        Comparator.nullsLast(Comparator.<BigDecimal>reverseOrder()))
                .thenComparing(Candidate::storeId)
                .thenComparing(Candidate::productId));
        return rows.stream().limit(maxRows).toList();
    }

    private double distanceTo(GeoPoint point, UUID storeId) {
        if (point == null) {
            return 0d;
        }
        Store shop = shops.get(storeId);
        return shop == null || shop.location() == null ? Double.MAX_VALUE : point.distanceMetresTo(shop.location());
    }

    // ------------------------------------------------------------------------------------ fixtures

    private ItemSearchService service() {
        return service(CAP);
    }

    private ItemSearchService service(int maxCandidates) {
        return new ItemSearchService(search, productRepository, storeRepository, storeService,
                Clock.fixed(NOW, ZoneOffset.UTC), RADIUS, maxCandidates, TIMEOUT);
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
        graded.put(product.getId(), new Candidate(product.getId(), shop.getId(), tier, score, 0));
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

    private static void refused(String code, Runnable search) {
        assertThatThrownBy(search::run)
                .isInstanceOfSatisfying(SearchRefusedException.class,
                        e -> assertThat(e.getCode()).isEqualTo(code));
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

        /**
         * The query leaves these out, but a product can be paused or sell out between the query and the
         * read. What the read says decides, and the shop's count loses what it dropped.
         */
        @Test
        void a_paused_draft_or_out_of_stock_product_never_appears_nor_counts() {
            Store shop = corner("Corner Grocer");
            sells(shop, "Pepsi 1L").pause();
            sells(shop, "Pepsi Max").applyStockProjection(false);
            sells(shop, "Pepsi Zero");
            Store other = downtown("Only A Draft");
            Product draft = new Product(other.getMerchantId(), other.getId(), "Pepsi 2L", null,
                    new BigDecimal("2.00"), null);
            products.put(draft.getId(), draft);

            ItemSearchResult result = searchNear("pepsi");

            assertThat(shopNames(result)).containsExactly("Corner Grocer");
            ShopMatch match = result.page().getContent().get(0);
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

        /**
         * The shop is what a customer orders from, so its matches travel together: the best three, and
         * the database's count of all of them, however many rows it kept.
         */
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
            sells(downtown("Middle Weaker Score"), "Pepsi Max", 1, 0.9d);
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
            for (int i = 0; i < 4; i++) {
                sells(shopAt("Shop " + i, 33.8980d + i * 0.001d, 35.4830d), "Pepsi 1L");
            }

            ItemSearchResult capped = service(3).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);
            ItemSearchResult whole = service(4).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);

            assertThat(capped.truncated()).isTrue();
            assertThat(capped.candidateLimit()).isEqualTo(3);
            assertThat(shopNames(capped)).containsExactly("Shop 0", "Shop 1", "Shop 2");
            assertThat(whole.truncated()).isFalse();
            assertThat(whole.page().getContent()).hasSize(4);
        }

        /**
         * One shop with more matches than it may show takes three rows, not all of them, and still says
         * how many it has: the ceiling is not spent on one shop.
         */
        @Test
        void a_shop_with_many_matches_takes_three_rows_and_keeps_its_count() {
            Store big = corner("Forty Kinds Of Pepsi");
            for (int i = 0; i < 40; i++) {
                sells(big, "Pepsi " + i);
            }
            sells(downtown("Downtown Grocer"), "Pepsi 1L");

            ItemSearchResult result = service(4).search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 20);

            assertThat(result.truncated()).isFalse();
            assertThat(shopNames(result)).containsExactly("Forty Kinds Of Pepsi", "Downtown Grocer");
            assertThat(result.page().getContent().get(0).items()).hasSize(3);
            assertThat(result.page().getContent().get(0).matchedInStore()).isEqualTo(40);
            assertThat((int) asked[13]).isEqualTo(ItemSearchService.ITEMS_PER_SHOP);
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
         * the sphere keeps; the sphere decides afterwards. One row more than the ceiling, three rows a
         * shop, and the service's own clock for "open now".
         */
        @Test
        void near_a_point_it_asks_for_the_widened_circle_three_a_shop_and_one_row_past_the_ceiling() {
            searchNear("pepsi");

            assertThat(asked[7]).isEqualTo(true);
            assertThat((double) asked[8]).isEqualTo(33.8977d);
            assertThat((double) asked[9]).isEqualTo(35.4829d);
            assertThat((double) asked[10]).isEqualTo(RADIUS * StoreService.RADIUS_SLACK);
            assertThat((double) asked[11]).isEqualTo(StoreService.RADIUS_SLACK);
            assertThat(asked[12]).isEqualTo(NOW);
            assertThat(asked[13]).isEqualTo(ItemSearchService.ITEMS_PER_SHOP);
            assertThat(asked[14]).isEqualTo(CAP + 1);
        }

        @Test
        void without_a_point_it_asks_for_no_circle_and_binds_no_null() {
            searchEverywhere("pepsi");

            assertThat(asked[7]).isEqualTo(false);
            assertThat((double) asked[8]).isZero();
            assertThat((double) asked[9]).isZero();
        }

        /**
         * q is the first slot, then the terms, each as the database folds it and its words longest first;
         * an unused slot and an absent barcode are '' and never null.
         */
        @Test
        void q_and_the_terms_fill_the_slots_in_order_folded_with_their_words_longest_first() {
            service().search(ItemQuery.of("  Nido Full CREAM milk  ", List.of("بيبسي"), null), HAMRA, 0, 10);

            assertThat(List.of(asked[0], asked[1], asked[2], asked[3], asked[4], asked[5], asked[6]))
                    .containsExactly("nido full cream milk", "cream nido full milk", "بيبسي", "بيبسي",
                            "", "", "");
        }

        /** A barcode alone has no words, so nothing is folded. */
        @Test
        void a_barcode_alone_fills_no_slot_and_folds_nothing() {
            service().search(ItemQuery.of(null, null, "5449000000996"), HAMRA, 0, 10);

            assertThat(List.of(asked[0], asked[1], asked[2], asked[3], asked[4], asked[5], asked[6]))
                    .containsExactly("", "", "", "", "", "", "5449000000996");
            verify(productRepository, never()).foldForSearch(anyString(), anyString(), anyString());
        }

        /**
         * A one-letter word ("1" and "l" of "1.5 l") is in the phrase but not among the words: most
         * names contain one, and no index can narrow by it.
         */
        @Test
        void a_one_letter_word_is_kept_in_the_phrase_and_left_out_of_the_words() {
            service().search(ItemQuery.of("Coca-Cola Zero 1.5 L", null, null), HAMRA, 0, 10);

            assertThat(asked[0]).isEqualTo("coca cola zero 1 5 l");
            assertThat(asked[1]).isEqualTo("coca cola zero");
        }

        /** The radius is the server's setting, held to "near me"'s bounds. */
        @Test
        void a_radius_setting_out_of_bounds_is_clamped() {
            new ItemSearchService(search, productRepository, storeRepository, storeService,
                    Clock.fixed(NOW, ZoneOffset.UTC), 900_000, CAP, TIMEOUT)
                    .search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10);

            assertThat((double) asked[10])
                    .isEqualTo(ItemSearchService.MAX_RADIUS_METRES * StoreService.RADIUS_SLACK);
        }
    }

    @Nested
    @DisplayName("what one search may cost the database")
    class Cost {

        /** The timeout is set before anything else is asked, so it bounds every statement of the search. */
        @Test
        void every_statement_runs_under_the_statement_timeout_set_first() {
            searchNear("pepsi");

            InOrder order = inOrder(search, productRepository);
            order.verify(search).limitStatementTime("2000");
            order.verify(productRepository).foldForSearch("pepsi", "", "");
            order.verify(search).findCandidates(anyString(), anyString(), anyString(), anyString(),
                    anyString(), anyString(), anyString(), anyBoolean(), anyDouble(), anyDouble(),
                    anyDouble(), anyDouble(), any(), anyInt(), anyInt());
        }

        /** A setting of a millisecond would fail every search, and one of minutes would hold a connection. */
        @Test
        void a_timeout_setting_out_of_bounds_is_clamped() {
            new ItemSearchService(search, productRepository, storeRepository, storeService,
                    Clock.fixed(NOW, ZoneOffset.UTC), RADIUS, CAP, Duration.ofMillis(1))
                    .search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10);
            new ItemSearchService(search, productRepository, storeRepository, storeService,
                    Clock.fixed(NOW, ZoneOffset.UTC), RADIUS, CAP, Duration.ofMinutes(5))
                    .search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10);

            verify(search).limitStatementTime("100");
            verify(search).limitStatementTime("15000");
        }

        /**
         * The database cancels a statement that runs past the timeout with SQLSTATE 57014, however the
         * layers above the driver wrap it. The search answers that as SEARCH_TIMED_OUT, a 503.
         */
        @Test
        void a_statement_the_database_cancelled_is_a_timed_out_search() {
            SQLException cancelled = new SQLException("canceling statement due to statement timeout", "57014");
            List<RuntimeException> wrappings = List.of(
                    new QueryTimeoutException("timed out", cancelled),
                    new jakarta.persistence.QueryTimeoutException("timed out"),
                    new RuntimeException(new jakarta.persistence.PersistenceException(cancelled)));
            for (RuntimeException wrapped : wrappings) {
                doThrow(wrapped).when(search).findCandidates(anyString(), anyString(), anyString(),
                        anyString(), anyString(), anyString(), anyString(), anyBoolean(), anyDouble(),
                        anyDouble(), anyDouble(), anyDouble(), any(), anyInt(), anyInt());

                assertThatThrownBy(() -> searchNear("pepsi"))
                        .as(wrapped.toString())
                        .isInstanceOfSatisfying(SearchTimedOutException.class, e -> {
                            assertThat(e.getCode()).isEqualTo(ItemSearchService.SEARCH_TIMED_OUT);
                            assertThat(e.getRetryAfterSeconds()).isPositive();
                            assertThat(e.getCause()).isSameAs(wrapped);
                        });
            }
        }

        /** Any other failure is not a timeout, and is not dressed up as one. */
        @Test
        void any_other_failure_passes_through_as_it_was() {
            RuntimeException down = new DataAccessResourceFailureException("connection lost",
                    new SQLException("terminating connection", "08006"));
            doThrow(down).when(search).findCandidates(anyString(), anyString(), anyString(), anyString(),
                    anyString(), anyString(), anyString(), anyBoolean(), anyDouble(), anyDouble(), anyDouble(),
                    anyDouble(), any(), anyInt(), anyInt());

            assertThatThrownBy(() -> searchNear("pepsi")).isSameAs(down);
        }
    }

    @Nested
    @DisplayName("what cannot be searched")
    class Refusals {

        @Test
        void nothing_or_one_character_is_too_short() {
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of(null, null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("   ", null, "  "));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("p", null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of(" p ", null, null));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> ItemQuery.of("pepsi", List.of(""), null));
            assertThat(ItemQuery.of("pe", null, null).terms()).containsExactly("pe");
        }

        /**
         * Counted as the database folds it: "a." is one letter, and "a b c d e" is five words of one, which
         * nothing can narrow by. Nothing is searched for either.
         */
        @Test
        void a_term_that_folds_to_no_word_of_two_characters_is_too_short() {
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> searchNear("a."));
            refused(ItemSearchService.SEARCH_TOO_SHORT, () -> searchNear("1 l"));
            refused(ItemSearchService.SEARCH_TOO_SHORT,
                    () -> searchNear("a b c d e f g h i j k l m n o p q r s t u v w x y z"));
            refused(ItemSearchService.SEARCH_TOO_SHORT,
                    () -> service().search(ItemQuery.of("pepsi", List.of("!!"), null), HAMRA, 0, 10));
            assertThat(asked).isNull();
        }

        /** Five words, counting only those of two characters or more; a sixth is refused, unsearched. */
        @Test
        void more_than_five_words_is_too_many() {
            refused(ItemSearchService.SEARCH_TOO_MANY_WORDS, () -> searchNear("ab cd ef gh ij kl"));
            refused(ItemSearchService.SEARCH_TOO_MANY_WORDS,
                    () -> searchNear("pepsi cola diet zero max light"));
            assertThat(asked).isNull();

            searchNear("ab cd ef gh ij");
            assertThat(asked[1]).isEqualTo("ab cd ef gh ij");
            searchNear("coca cola zero diet can 1 5 l");
            assertThat(asked[1]).isEqualTo("coca cola zero diet can");
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
