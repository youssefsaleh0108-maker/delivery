package com.delivery.product.domain;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsRequest;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.OnboardingApplicationClient;
import com.delivery.product.service.PopularServiceShops;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.ServiceOfferSearch;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.NearbyStoreView;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.Mockito.mock;

/**
 * V34, V35 and the services reads, against a real PostgreSQL with PostGIS.
 *
 * <p>The unit suite proves which queries the catalogue asks; only a database proves what they answer
 * and that the schema holds: the CHECKs, the foreign key the terms are inserted after, a status literal
 * inside a subquery two levels deep. Built like {@code ServicesVerticalDatabaseTest}, and for the same
 * reason: the entity manager validates every entity against the migrated schema, as the service does at
 * boot ({@code ddl-auto: validate}), so a {@code ServiceTerms} that disagreed with V34 fails here before
 * it fails a pod.
 *
 * <p>Offers are created, published, paused and resumed through the real {@code CatalogService}, so the
 * rules and the SQL are exercised together.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a schema of
 * its own with a random name and drops only that schema, so it cannot touch a real one:
 *
 * <pre>
 * docker run -d --name product-it -e POSTGRES_PASSWORD=it -p 55433:5432 postgis/postgis:17-3.5
 * PRODUCT_TEST_DB_URL=jdbc:postgresql://localhost:55433/postgres PRODUCT_TEST_DB_PASSWORD=it \
 *     mvn -Dtest=ServiceOffersDatabaseTest test
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("service offers, against a real database")
class ServiceOffersDatabaseTest {

    private static final Instant NOW = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

    private static final PageRequest PAGE = PageRequest.of(0, 50);

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "svc_offers_it_" + UUID.randomUUID().toString().substring(0, 8);

    /** A goods shop's products that were on the schema before V34 and V35, by status. */
    private final Map<String, UUID> productsBeforeV34 = new HashMap<>();

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private ProductRepository products;
    private ServiceTermsRepository serviceTerms;
    private CatalogService catalog;

    /** With the launch categories open. */
    private ServiceOfferSearch search;

    private UUID grill;
    private UUID platter;
    private Store press;
    private Product cards;
    private Product banner;
    private Product sofa;
    private Product flyers;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

    @BeforeAll
    void migrateOverProductsOnSaleThenSeedOffers() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // What infra/postgres/init provides on every environment.
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
            statement.execute("CREATE SCHEMA " + schema);
        }

        // The schema as dev and qa have it with slice 1 deployed, with a goods shop's products on it.
        flyway(MigrationVersion.fromVersion("33")).migrate();
        grill = insertGoodsShop("Hamra Grill");
        for (String status : List.of("DRAFT", "ACTIVE", "ARCHIVED")) {
            productsBeforeV34.put(status, insertRawProduct(grill, "Grill " + status, status));
        }
        platter = insertRawProduct(grill, "Print shop platter", "ACTIVE");

        // Then this change. A CHECK an existing row failed would make this throw.
        flyway(MigrationVersion.LATEST).migrate();

        entityManagerFactory = entityManagerFactory();
        em = entityManagerFactory.createEntityManager();
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(em);
        StoreRepository stores = repositories.getRepository(StoreRepository.class);
        CategoryRepository categories = repositories.getRepository(CategoryRepository.class);
        products = repositories.getRepository(ProductRepository.class);
        serviceTerms = repositories.getRepository(ServiceTermsRepository.class);

        StoreService storeService = new StoreService(stores,
                repositories.getRepository(StoreOfferRepository.class),
                repositories.getRepository(StoreFavoriteRepository.class), products, categories,
                new ServiceCategories(new MockEnvironment()), mock(OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC),
                Duration.ofHours(4), "Asia/Beirut");
        catalog = new CatalogService(products, categories, storeService, mock(OutboxRecorder.class),
                stores, serviceTerms, repositories.getRepository(StoreDeliveryZoneRepository.class),
                repositories.getRepository(ProductOptionGroupRepository.class),
                new ServiceCategories(new MockEnvironment()));
        search = searchWith(new MockEnvironment());

        transaction(() -> {
            press = listed(new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING));
            Store cleaners = listed(new Store("merchant-clean", "Spotless Cleaners",
                    Store.Vertical.SERVICES, Store.ServiceCategory.CLEANING));
            // Created and never listed.
            Store draftPress = new Store("merchant-draft", "Not Yet Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING);
            em.persist(press);
            em.persist(cleaners);
            em.persist(draftPress);

            cards = liveOffer(press, "Business card printing", ServiceTerms.Fulfilment.BOTH);
            banner = liveOffer(press, "Banner printing", ServiceTerms.Fulfilment.PICKUP);
            catalog.pause(banner.getId(), press.getMerchantId());
            sofa = liveOffer(cleaners, "Sofa cleaning", ServiceTerms.Fulfilment.PICKUP);
            flyers = liveOffer(draftPress, "Flyer printing", ServiceTerms.Fulfilment.PICKUP);

            ProductOptionGroup paper = new ProductOptionGroup(cards.getId(), "Paper type", 1, 1, 0);
            paper.replaceOptions(List.of(
                    new ProductOption("Matte", new BigDecimal("1.00"), true, 0),
                    new ProductOption("Premium", new BigDecimal("2.50"), false, 1)));
            em.persist(paper);
            return null;
        });
        em.clear();

        // Delivered orders, as order.delivered projects them: one row per order and product.
        deliveredIn(cards.getId(), press.getId(), 3);
        deliveredIn(banner.getId(), press.getId(), 5);
        deliveredIn(sofa.getId(), sofa.getStoreId(), 6);
        deliveredIn(flyers.getId(), flyers.getStoreId(), 4);
        deliveredIn(platter, grill, 9);
    }

    @AfterAll
    void dropTheSchema() throws SQLException {
        if (em != null) {
            // A set-up that failed half way leaves its transaction open, and an open transaction holds
            // locks the DROP below would wait on for ever. Closing the manager does not release them.
            if (em.getTransaction().isActive()) {
                em.getTransaction().rollback();
            }
            em.close();
        }
        if (entityManagerFactory != null) {
            entityManagerFactory.close();
        }
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // Bounded, so a lock nobody released fails the clean-up instead of hanging the build.
            statement.execute("SET lock_timeout = '30s'");
            statement.execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
        }
    }

    // ------------------------------------------------------------------------------------ the migrations

    @Test
    @DisplayName("V34 and V35 apply over products already on sale, and leave every one as it was")
    void the_migrations_apply_over_products_on_sale() throws SQLException {
        assertThat(count("SELECT count(*) FROM flyway_schema_history "
                + "WHERE version IN ('34', '35') AND success")).isEqualTo(2);
        for (Map.Entry<String, UUID> before : productsBeforeV34.entrySet()) {
            assertThat(text("SELECT status FROM products WHERE id = '" + before.getValue() + "'"))
                    .isEqualTo(before.getKey());
        }
        assertThat(count("SELECT count(*) FROM service_terms t JOIN products p ON p.id = t.product_id "
                + "WHERE p.store_id = '" + grill + "'")).isZero();
    }

    @Test
    @DisplayName("the schema refuses what no offer can be, and accepts a paused product")
    void the_schema_refuses_what_no_offer_can_be() throws SQLException {
        UUID draft = productsBeforeV34.get("DRAFT");

        assertThatThrownBy(() -> insertRawTerms(draft, "QUOTE", 1, 24, 48, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_pricing_type");
        assertThatThrownBy(() -> insertRawTerms(draft, "FIXED", 1, 48, 24, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_turnaround");
        assertThatThrownBy(() -> insertRawTerms(draft, "FIXED", 1, 0, 0, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_turnaround");
        assertThatThrownBy(() -> insertRawTerms(draft, "PER_UNIT", 10, 24, 48, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_per_unit_is_one_unit");
        assertThatThrownBy(() -> insertRawTerms(draft, "FIXED", 0, 24, 48, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_unit_size");
        assertThatThrownBy(() -> insertRawTerms(draft, "FIXED", 1, 24, 48, "COURIER", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_fulfilment");
        assertThatThrownBy(() -> insertRawTerms(draft, "FIXED", 1, 24, 48, "PICKUP", "TWO_FILES"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_service_terms_attachment");
        assertThatThrownBy(() -> insertRawTerms(UUID.randomUUID(), "FIXED", 1, 24, 48, "PICKUP", "NONE"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("service_terms_product_id_fkey");

        assertThatThrownBy(() -> execute("UPDATE products SET status = 'HIDDEN' WHERE id = '" + draft + "'"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_product_status");
        execute("UPDATE products SET status = 'PAUSED' WHERE id = '" + draft + "'");
        assertThat(text("SELECT status FROM products WHERE id = '" + draft + "'")).isEqualTo("PAUSED");
        execute("UPDATE products SET status = 'DRAFT' WHERE id = '" + draft + "'");
    }

    // ------------------------------------------------------------------------------------ the offers

    @Test
    @DisplayName("an offer's terms are saved beside it and read back as they were set")
    void terms_are_saved_beside_the_offer() {
        ServiceTerms terms = serviceTerms.findById(cards.getId()).orElseThrow();

        assertThat(terms.getPricingType()).isEqualTo(ServiceTerms.PricingType.FIXED);
        assertThat(terms.getUnitLabel()).isEqualTo("cards");
        assertThat(terms.getUnitSize()).isEqualTo(500);
        assertThat(terms.getTurnaroundMinHours()).isEqualTo(24);
        assertThat(terms.getTurnaroundMaxHours()).isEqualTo(48);
        assertThat(terms.getFulfilmentModes()).isEqualTo(ServiceTerms.Fulfilment.BOTH);
        assertThat(terms.getAttachmentPolicy()).isEqualTo(ServiceTerms.AttachmentPolicy.OPTIONAL);
        assertThat(terms.getInstructionsPrompt()).isEqualTo("Which paper colour?");
        assertThat(products.findById(banner.getId()).orElseThrow().getStatus())
                .isEqualTo(Product.Status.PAUSED);
        em.clear();
    }

    @Test
    @DisplayName("an offer's From price counts the cheapest paper it must be printed on")
    void the_from_price_reads_the_options_from_the_database() {
        ProductView view = catalog.view(products.findById(cards.getId()).orElseThrow());

        assertThat(view.service()).isNotNull();
        assertThat(view.fromPrice()).isEqualTo(new BigDecimal("16.00"));
        em.clear();
    }

    @Test
    @DisplayName("the search lists live offers of listed service shops in open categories, and nothing else")
    void the_services_search_is_scoped() {
        assertThat(names(search.search(null, null, PAGE)))
                .contains("Business card printing")
                .doesNotContain("Banner printing", "Sofa cleaning", "Flyer printing",
                        "Print shop platter", "Grill ACTIVE");
        assertThat(names(search.search("print", null, PAGE)))
                .contains("Business card printing")
                .doesNotContain("Print shop platter", "Banner printing", "Flyer printing");
        assertThat(search.search("banner", null, PAGE).getTotalElements()).isZero();
        assertThat(search.search(null, Store.ServiceCategory.CLEANING, PAGE).getContent()).isEmpty();

        ServiceOfferSearch cleaningOpen =
                searchWith(new MockEnvironment().withProperty(OPEN_CATEGORIES, "PRINTING,CLEANING"));
        assertThat(names(cleaningOpen.search(null, Store.ServiceCategory.CLEANING, PAGE)))
                .containsExactly("Sofa cleaning");
        em.clear();
    }

    @Test
    @DisplayName("pausing takes an offer off the search and the shop's shelf, and resuming brings it back")
    void pausing_and_resuming_move_an_offer_off_and_on_sale() {
        Product poster = transaction(() ->
                liveOffer(press, "Poster printing", ServiceTerms.Fulfilment.PICKUP));
        em.clear();
        assertThat(names(search.search("poster", null, PAGE))).containsExactly("Poster printing");

        transaction(() -> catalog.pause(poster.getId(), press.getMerchantId()));
        em.clear();
        assertThat(search.search("poster", null, PAGE).getTotalElements()).isZero();
        assertThat(names(products.findActiveInStore(press.getId(), null, "%", PAGE)))
                .contains("Business card printing")
                .doesNotContain("Poster printing", "Banner printing");

        transaction(() -> catalog.resume(poster.getId(), press.getMerchantId()));
        em.clear();
        assertThat(names(search.search("poster", null, PAGE))).containsExactly("Poster printing");

        transaction(() -> catalog.archive(poster.getId(), press.getMerchantId()));
        em.clear();
    }

    @Test
    @DisplayName("an offer of a shop that is not listed, and that shop's shelf, are its provider's alone")
    void offers_of_unlisted_shops_are_their_providers_alone() {
        // Listed, in an open category: anybody reads it and its shelf.
        assertThat(catalog.read(cards.getId(), "customer-sub").getName())
                .isEqualTo("Business card printing");
        assertThat(names(catalog.browseStore(press.getId(), "customer-sub", null, null, PAGE)))
                .contains("Business card printing");

        // Spotless Cleaners is listed in a category the launch keeps closed; Not Yet Press never listed.
        assertThatThrownBy(() -> catalog.read(sofa.getId(), "customer-sub"))
                .isInstanceOf(CatalogService.ProductNotFoundException.class);
        assertThatThrownBy(() -> catalog.read(flyers.getId(), null))
                .isInstanceOf(CatalogService.ProductNotFoundException.class);
        assertThatThrownBy(() -> catalog.browseStore(sofa.getStoreId(), "customer-sub", null, null, PAGE))
                .isInstanceOf(StoreService.StoreNotFoundException.class);

        assertThat(catalog.read(sofa.getId(), "merchant-clean").getName()).isEqualTo("Sofa cleaning");
        assertThat(names(catalog.browseStore(sofa.getStoreId(), "merchant-clean", null, null, PAGE)))
                .containsExactly("Sofa cleaning");
        em.clear();
    }

    @Test
    @DisplayName("the dashboard's count is the database's count of one merchant's offers in a status")
    void the_status_count_is_the_databases() {
        assertThat(products.findByMerchantIdAndStatus(press.getMerchantId(), Product.Status.ACTIVE,
                PageRequest.of(0, 1)).getTotalElements()).isEqualTo(1);
        assertThat(products.findByMerchantIdAndStatus(press.getMerchantId(), Product.Status.PAUSED,
                PageRequest.of(0, 1)).getTotalElements()).isEqualTo(1);
        assertThat(products.findByMerchantIdAndStatus("merchant-clean", Product.Status.ACTIVE,
                PageRequest.of(0, 1)).getTotalElements()).isEqualTo(1);
        em.clear();
    }

    @Test
    @DisplayName("an account with a goods shop and a print shop counts each shop's offers apart")
    void a_two_shop_account_counts_each_shop_apart() {
        String merchant = "merchant-two-shops";
        Store bakery = transaction(() -> {
            Store shop = listed(new Store(merchant, "Two Shops Bakery", Store.Vertical.RESTAURANT));
            em.persist(shop);
            return shop;
        });
        Store printer = transaction(() -> {
            Store shop = listed(new Store(merchant, "Two Shops Printer", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING));
            em.persist(shop);
            return shop;
        });
        transaction(() -> {
            for (String name : List.of("Two shops cake", "Two shops bread")) {
                Product dish = catalog.create(merchant, new ProductRequest(name, null,
                        new BigDecimal("4.00"), null, bakery.getId(), null, null, null),
                        StoreService.FirstShop.ALREADY_OPEN);
                dish.addImage("products/" + UUID.randomUUID() + ".jpg");
                catalog.publish(dish.getId(), merchant);
            }
            liveOffer(printer, "Two shops invitations", ServiceTerms.Fulfilment.PICKUP);
            return null;
        });
        em.clear();

        assertThat(products.findByMerchantIdAndStatus(merchant, Product.Status.ACTIVE,
                PageRequest.of(0, 1)).getTotalElements()).isEqualTo(3);
        assertThat(products.findByMerchantIdAndStoreIdAndStatus(merchant, printer.getId(),
                Product.Status.ACTIVE, PageRequest.of(0, 1)).getTotalElements()).isEqualTo(1);
        assertThat(products.findByMerchantIdAndStoreIdAndStatus(merchant, bakery.getId(),
                Product.Status.ACTIVE, PageRequest.of(0, 1)).getTotalElements()).isEqualTo(2);
        assertThat(names(products.findByMerchantIdAndStoreId(merchant, printer.getId(), PAGE)))
                .containsExactly("Two shops invitations");
        em.clear();
    }

    @Test
    @DisplayName("Popular near you ranks nearby listed service shops by the orders they delivered in 30 days")
    void popular_near_you_ranks_nearby_listed_service_shops_by_recent_orders() throws SQLException {
        // Jounieh: about twelve kilometres from the Beirut shops set up above, so outside any circle
        // drawn around it. Every shop here is due north of it by the kilometres given.
        double jounieh = 33.980800d;
        Store photos = transaction(() -> shopNorthOf(jounieh, 3.0, "Kaslik Photo Lab",
                Store.Vertical.SERVICES, Store.ServiceCategory.PHOTOGRAPHY));
        Store printer = transaction(() -> shopNorthOf(jounieh, 1.0, "Jounieh Print House",
                Store.Vertical.SERVICES, Store.ServiceCategory.PRINTING));
        Store tailor = transaction(() -> shopNorthOf(jounieh, 1.0, "Bay Tailors",
                Store.Vertical.SERVICES, Store.ServiceCategory.TAILORING));
        Store repairs = transaction(() -> shopNorthOf(jounieh, 2.0, "Fix It Jounieh",
                Store.Vertical.SERVICES, Store.ServiceCategory.REPAIRS));
        Store farRepairs = transaction(() -> shopNorthOf(jounieh, 8.0, "Byblos Repairs",
                Store.Vertical.SERVICES, Store.ServiceCategory.REPAIRS));
        Store quiet = transaction(() -> shopNorthOf(jounieh, 1.5, "Quiet Frames",
                Store.Vertical.SERVICES, Store.ServiceCategory.PHOTOGRAPHY));
        Store stale = transaction(() -> shopNorthOf(jounieh, 1.5, "Last Year's Tailor",
                Store.Vertical.SERVICES, Store.ServiceCategory.TAILORING));
        Store beauty = transaction(() -> shopNorthOf(jounieh, 0.5, "Glow Salon",
                Store.Vertical.SERVICES, Store.ServiceCategory.BEAUTY));
        Store suspended = transaction(() -> {
            Store shop = shopNorthOf(jounieh, 0.5, "Shut Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING);
            shop.suspend();
            return shop;
        });
        Store bakery = transaction(() -> shopNorthOf(jounieh, 0.5, "Jounieh Bakery",
                Store.Vertical.RESTAURANT, null));
        em.clear();

        Instant recently = NOW.minus(Duration.ofDays(2));
        deliveredOrders(photos.getId(), 7, 1, recently);
        // Four recent orders and one on the window's edge, 29 days ago, which still counts.
        deliveredOrders(printer.getId(), 4, 1, recently);
        deliveredOrders(printer.getId(), 1, 1, NOW.minus(Duration.ofDays(29)));
        // Five orders of three lines each: five orders, not the fifteen that would lead the row.
        deliveredOrders(tailor.getId(), 5, 3, recently);
        deliveredOrders(repairs.getId(), 5, 1, recently);
        execute("UPDATE stores SET rating = 4.9, rating_count = 20 WHERE id = '" + printer.getId() + "'");
        execute("UPDATE stores SET rating = 4.2, rating_count = 12 WHERE id = '" + tailor.getId() + "'");
        // Each of these would lead the row if it counted: too far, a closed category, suspended, goods.
        deliveredOrders(farRepairs.getId(), 9, 1, recently);
        deliveredOrders(beauty.getId(), 9, 1, recently);
        deliveredOrders(suspended.getId(), 9, 1, recently);
        deliveredOrders(bakery.getId(), 9, 1, recently);
        // Below the floor: two orders in all, and one recent order after ten delivered 31 days ago.
        deliveredOrders(quiet.getId(), 2, 1, recently);
        deliveredOrders(stale.getId(), 1, 1, recently);
        deliveredOrders(stale.getId(), 10, 1, NOW.minus(Duration.ofDays(31)));

        GeoPoint centre = GeoPoint.of(jounieh, 35.617800d);
        PopularServiceShops popular = popularShops(new MockEnvironment());

        List<NearbyStoreView> row = popular.near(centre, null, 10);
        // Most delivered first; the three-way tie at five goes to the better rated, the unrated last.
        assertThat(row).extracting(near -> near.store().store().getName())
                .containsExactly("Kaslik Photo Lab", "Jounieh Print House", "Bay Tailors", "Fix It Jounieh");
        assertThat(row.get(0).distanceMetres()).isCloseTo(3000d, within(10d));

        assertThat(popular.near(centre, null, 2)).extracting(near -> near.store().store().getName())
                .containsExactly("Kaslik Photo Lab", "Jounieh Print House");
        assertThat(popular.near(centre, Store.ServiceCategory.PRINTING, 10))
                .extracting(near -> near.store().store().getName())
                .containsExactly("Jounieh Print House");
        assertThat(popular.near(centre, Store.ServiceCategory.BEAUTY, 10)).isEmpty();
        // Around Beirut, only the listed print shop set up above: the cleaners' category is closed, the
        // draft press is not listed, and the grill sells goods.
        assertThat(popular.near(GeoPoint.of(33.898200d, 35.482500d), null, 10))
                .extracting(near -> near.store().store().getName())
                .containsExactly("Al Fakhry Press");
        em.clear();
    }

    // ------------------------------------------------------------------------------------ helpers

    private ServiceOfferSearch searchWith(MockEnvironment environment) {
        return new ServiceOfferSearch(products, new ServiceCategories(environment));
    }

    /** The popular row with the service's default settings: five kilometres, thirty days, three orders. */
    private PopularServiceShops popularShops(MockEnvironment environment) {
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(em);
        StoreRepository stores = repositories.getRepository(StoreRepository.class);
        StoreService storeService = new StoreService(stores,
                repositories.getRepository(StoreOfferRepository.class),
                repositories.getRepository(StoreFavoriteRepository.class), products,
                repositories.getRepository(CategoryRepository.class), new ServiceCategories(environment),
                mock(OnboardingApplicationClient.class), Clock.fixed(NOW, ZoneOffset.UTC),
                Duration.ofHours(4), "Asia/Beirut");
        return new PopularServiceShops(stores, storeService, new ServiceCategories(environment),
                Clock.fixed(NOW, ZoneOffset.UTC), 5000, 30, 3);
    }

    /** A listed shop, persisted, {@code kilometres} due north of a point on Jounieh's meridian. */
    private Store shopNorthOf(double latitude, double kilometres, String name, Store.Vertical vertical,
                              Store.ServiceCategory category) {
        Store shop = category == null
                ? new Store("merchant-" + UUID.randomUUID(), name, vertical)
                : new Store("merchant-" + UUID.randomUUID(), name, vertical, category);
        listed(shop);
        shop.pinAt(GeoPoint.of(latitude + kilometres / 111.195d, 35.617800d));
        em.persist(shop);
        return shop;
    }

    /** {@code orders} delivered orders of one shop, each of {@code lines} lines, delivered {@code at}. */
    private void deliveredOrders(UUID storeId, int orders, int lines, Instant at) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO delivered_order_lines (order_id, product_id, store_id, qty, "
                             + "delivered_at) VALUES (?, ?, ?, 1, ?)")) {
            for (int order = 0; order < orders; order++) {
                UUID orderId = UUID.randomUUID();
                for (int line = 0; line < lines; line++) {
                    insert.setObject(1, orderId);
                    insert.setObject(2, UUID.randomUUID());
                    insert.setObject(3, storeId);
                    insert.setObject(4, java.time.OffsetDateTime.ofInstant(at, ZoneOffset.UTC));
                    insert.executeUpdate();
                }
            }
        }
    }

    private <T> T transaction(Supplier<T> work) {
        em.getTransaction().begin();
        try {
            T result = work.get();
            em.getTransaction().commit();
            return result;
        } catch (RuntimeException e) {
            if (em.getTransaction().isActive()) {
                em.getTransaction().rollback();
            }
            throw e;
        }
    }

    /** Created, given a photo and published through the catalogue, with a print shop's terms. */
    private Product liveOffer(Store shop, String name, ServiceTerms.Fulfilment fulfilment) {
        Product offer = catalog.create(shop.getMerchantId(), new ProductRequest(name, null,
                new BigDecimal("15.00"), null, shop.getId(), null, null,
                new ServiceTermsRequest(ServiceTerms.PricingType.FIXED, "cards", 500, 24, 48,
                        fulfilment, ServiceTerms.AttachmentPolicy.OPTIONAL, "Which paper colour?")),
                StoreService.FirstShop.ALREADY_OPEN);
        offer.addImage("products/" + UUID.randomUUID() + ".jpg");
        return catalog.publish(offer.getId(), shop.getMerchantId());
    }

    /** Listed, pinned and open all week. */
    private static Store listed(Store store) {
        store.pinAt(GeoPoint.of(33.898200d, 35.482500d));
        store.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        store.publish(NOW.minus(Duration.ofDays(30)));
        return store;
    }

    private static List<String> names(Page<Product> page) {
        return page.getContent().stream().map(Product::getName).toList();
    }

    private Flyway flyway(MigrationVersion target) {
        return Flyway.configure()
                .dataSource(url, user, password)
                .schemas(schema)
                .defaultSchema(schema)
                // The locations and the ordering rule application.yml gives the service.
                .locations("classpath:db/migration/shared", "classpath:db/migration/product")
                .outOfOrder(true)
                .target(target)
                .load();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it.
        jpa.put("hibernate.hbm2ddl.auto", "validate");
        jpa.put("hibernate.default_schema", schema);
        // Not the service's hibernate.jdbc.time_zone=UTC, for the reason ServicesVerticalDatabaseTest
        // gives: on a machine outside UTC it shifts the all-week opening hours past chk_hours_order.
        jpa.put("hibernate.physical_naming_strategy",
                "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy");
        jpa.put("hibernate.implicit_naming_strategy",
                "org.springframework.boot.orm.jpa.hibernate.SpringImplicitNamingStrategy");
        factory.setJpaPropertyMap(jpa);
        factory.afterPropertiesSet();
        return factory.getObject();
    }

    private String urlInSchema() {
        return url + (url.contains("?") ? "&" : "?") + "currentSchema=" + schema;
    }

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(urlInSchema(), user, password);
    }

    private long count(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getLong(1);
        }
    }

    private String text(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getString(1);
        }
    }

    private void execute(String sql) throws SQLException {
        try (Connection connection = connection(); Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    /** A goods shop as the schema before V34 holds it. */
    private UUID insertGoodsShop(String name) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO stores (id, merchant_id, name, slug, vertical, status, published_at) "
                             + "VALUES (?, 'merchant-it', ?, ?, 'RESTAURANT', 'ACTIVE', now())")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setString(2, name);
            insert.setString(3, "it-" + id);
            insert.executeUpdate();
            return id;
        }
    }

    /** A product as the schema before V34 holds it, with a photo. */
    private UUID insertRawProduct(UUID storeId, String name, String status) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO products (id, merchant_id, store_id, name, price, status, image_refs) "
                             + "VALUES (?, 'merchant-it', ?, ?, 16.00, ?, '[\"products/it.jpg\"]'::jsonb)")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setObject(2, storeId);
            insert.setString(3, name);
            insert.setString(4, status);
            insert.executeUpdate();
            return id;
        }
    }

    private void insertRawTerms(UUID productId, String pricingType, int unitSize, int minHours,
                                int maxHours, String fulfilment, String attachment) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO service_terms (product_id, pricing_type, unit_size, "
                             + "turnaround_min_hours, turnaround_max_hours, fulfilment_modes, "
                             + "attachment_policy) VALUES (?, ?, ?, ?, ?, ?, ?)")) {
            insert.setObject(1, productId);
            insert.setString(2, pricingType);
            insert.setInt(3, unitSize);
            insert.setInt(4, minHours);
            insert.setInt(5, maxHours);
            insert.setString(6, fulfilment);
            insert.setString(7, attachment);
            insert.executeUpdate();
        }
    }

    /** {@code orders} delivered orders, each with one line of this product. */
    private void deliveredIn(UUID productId, UUID storeId, int orders) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO delivered_order_lines (order_id, product_id, store_id, qty, "
                             + "delivered_at) VALUES (?, ?, ?, 500, now())")) {
            for (int i = 0; i < orders; i++) {
                insert.setObject(1, UUID.randomUUID());
                insert.setObject(2, productId);
                insert.setObject(3, storeId);
                insert.executeUpdate();
            }
        }
    }
}
