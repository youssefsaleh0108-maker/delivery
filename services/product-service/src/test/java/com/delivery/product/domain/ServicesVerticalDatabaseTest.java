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

import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.StoreService;
import com.delivery.product.service.StoreService.NearbyFilters;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * V33 and storefront isolation, against a real PostgreSQL with PostGIS.
 *
 * <p>Everything else in this module runs without a database, so the SQL that keeps a service shop off
 * the goods storefront would otherwise be checked by nothing before it reached dev: a literal in a
 * JPQL WHERE, a CASE in the PostGIS candidate query, a subquery in the catalogue, a CHECK in the
 * migration. A mock proves which query was asked; only a database proves what it answers.
 *
 * <p>The entity manager here validates every entity against the migrated schema, which is exactly
 * what the service does at boot ({@code ddl-auto: validate}). If {@code Store} and V33 disagreed, the
 * pod would refuse to start; here the test refuses first.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a schema of
 * its own with a random name and drops only that schema, so it cannot touch a real one:
 *
 * <pre>
 * docker run -d --name product-it -e POSTGRES_PASSWORD=it -p 55433:5432 postgis/postgis:17-3.5
 * PRODUCT_TEST_DB_URL=jdbc:postgresql://localhost:55433/postgres PRODUCT_TEST_DB_PASSWORD=it \
 *     mvn -Dtest=ServicesVerticalDatabaseTest test
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("the services vertical, against a real database")
class ServicesVerticalDatabaseTest {

    /** Hamra, Beirut: where the customer is standing. */
    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);

    private static final Instant NOW = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    private static final String OPEN_CATEGORIES = "delivery.product.services.enabled-categories";

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "svc_vertical_it_" + UUID.randomUUID().toString().substring(0, 8);

    /** How many shops were trading before V33 ran: the demo storefront's and the two below. */
    private long shopsBeforeV33;

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private JpaRepositoryFactory repositories;
    private StoreRepository stores;
    private ProductRepository products;

    /** With the launch categories open, as shipped. */
    private StoreService service;

    /** With Cleaning opened in configuration. */
    private StoreService serviceWithCleaningOpen;

    private Store grill;
    private Store press;
    private Store cleaners;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

    @BeforeAll
    void migrateOverTradingShopsThenSeedServiceShops() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // What infra/postgres/init provides on every environment.
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
            statement.execute("CREATE SCHEMA " + schema);
        }

        // The schema as dev and qa have it today, with shops trading on it.
        flyway(MigrationVersion.fromVersion("32")).migrate();
        insertGoodsShop("Hamra Kebab Corner", "RESTAURANT", 33.898600d, 35.483400d, "Hamra");
        insertGoodsShop("Hamra Corner Grocer", "GROCERY", 33.897000d, 35.481000d, "Hamra");
        shopsBeforeV33 = count("SELECT count(*) FROM stores");

        // Then this change. A CHECK that an existing row failed would make this throw.
        flyway(MigrationVersion.LATEST).migrate();

        entityManagerFactory = entityManagerFactory();
        em = entityManagerFactory.createEntityManager();
        repositories = new JpaRepositoryFactory(em);
        stores = repositories.getRepository(StoreRepository.class);
        products = repositories.getRepository(ProductRepository.class);

        UUID aisle = firstPlatformCategory();
        em.getTransaction().begin();
        grill = em.createQuery("SELECT s FROM Store s WHERE s.name = 'Hamra Kebab Corner'", Store.class)
                .getSingleResult();
        press = listedAt(new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING), 33.898200d, 35.482500d);
        cleaners = listedAt(new Store("merchant-clean", "Spotless Cleaners", Store.Vertical.SERVICES,
                Store.ServiceCategory.CLEANING), 33.898900d, 35.484100d);
        em.persist(press);
        em.persist(cleaners);
        em.persist(liveProduct(grill, "Mixed grill platter", aisle));
        em.persist(liveProduct(press, "500 business cards", aisle));
        // Starred: a goods shop, a service shop in an open category, and one in a closed category.
        em.persist(new StoreFavorite("customer-it", grill.getId()));
        em.persist(new StoreFavorite("customer-it", press.getId()));
        em.persist(new StoreFavorite("customer-it", cleaners.getId()));
        em.getTransaction().commit();
        em.clear();

        service = storeService(new MockEnvironment());
        serviceWithCleaningOpen = storeService(
                new MockEnvironment().withProperty(OPEN_CATEGORIES, "PRINTING,CLEANING"));
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

    // ------------------------------------------------------------------------------------ the migration

    @Test
    @DisplayName("V33 applies over shops already trading and leaves every one of them a goods shop")
    void v33_applies_over_trading_shops() throws SQLException {
        assertThat(count("SELECT count(*) FROM flyway_schema_history WHERE version = '33' AND success"))
                .isEqualTo(1);
        assertThat(shopsBeforeV33).isGreaterThanOrEqualTo(2);
        assertThat(count("SELECT count(*) FROM stores WHERE vertical <> 'SERVICES' "
                + "AND service_category IS NULL")).isEqualTo(shopsBeforeV33);
        assertThat(count("SELECT count(*) FROM stores WHERE name = 'Hamra Kebab Corner' "
                + "AND vertical = 'RESTAURANT' AND status = 'ACTIVE'")).isEqualTo(1);
    }

    @Test
    @DisplayName("the CHECKs hold the vertical and the category together, in both directions")
    void the_checks_hold_vertical_and_category_together() {
        assertThatThrownBy(() -> insertRawShop("SERVICES", null))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_store_service_category_vertical");
        assertThatThrownBy(() -> insertRawShop("GROCERY", "PRINTING"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_store_service_category_vertical");
        assertThatThrownBy(() -> insertRawShop("SERVICES", "KNITTING"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("\"chk_store_service_category\"");
        // A Services chip on Home is refused by the database too.
        assertThatThrownBy(() -> execute("UPDATE categories SET vertical = 'SERVICES' "
                + "WHERE id = (SELECT id FROM categories WHERE store_id IS NULL AND vertical IS NULL "
                + "LIMIT 1)"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_category_vertical");
    }

    // ------------------------------------------------------------------------------------ the reads

    @Test
    @DisplayName("Home's storefront and its search list goods shops and never a service shop")
    void home_never_lists_a_service_shop() {
        assertThat(storefrontNames(service, null, null, null))
                .contains("Hamra Kebab Corner", "Hamra Corner Grocer")
                .doesNotContain("Al Fakhry Press", "Spotless Cleaners");
        assertThat(storefrontNames(service, null, null, "fakhry")).isEmpty();

        // The goods query refuses a service shop even when it is asked for one directly.
        assertThat(stores.findStorefront(Store.Vertical.SERVICES, "%", null, null, null, null,
                PageRequest.of(0, 50))).isEmpty();
    }

    @Test
    @DisplayName("the Services tab lists service shops in open categories only")
    void the_services_tab_lists_open_categories_only() {
        assertThat(storefrontNames(service, Store.Vertical.SERVICES, null, null))
                .containsExactly("Al Fakhry Press");
        assertThat(storefrontNames(service, null, Store.ServiceCategory.PRINTING, "fakhry"))
                .containsExactly("Al Fakhry Press");
        assertThat(storefrontNames(service, Store.Vertical.SERVICES, Store.ServiceCategory.CLEANING,
                null)).isEmpty();
        assertThat(storefrontNames(serviceWithCleaningOpen, Store.Vertical.SERVICES, null, null))
                .containsExactlyInAnyOrder("Al Fakhry Press", "Spotless Cleaners");
    }

    @Test
    @DisplayName("near me leaves service shops out unless asked, in the SQL as well as in Java")
    void near_me_leaves_service_shops_out_unless_asked() {
        assertThat(nearbyNames(service, NearbyFilters.NONE))
                .contains("Hamra Kebab Corner", "Hamra Corner Grocer")
                .doesNotContain("Al Fakhry Press", "Spotless Cleaners");
        assertThat(nearbyNames(service, asking(Store.Vertical.SERVICES, null)))
                .containsExactly("Al Fakhry Press");
        assertThat(nearbyNames(serviceWithCleaningOpen, asking(null, Store.ServiceCategory.CLEANING)))
                .containsExactly("Spotless Cleaners");

        // The candidate query on its own, which is where the ceiling on candidates is counted.
        assertThat(candidates("", "PRINTING,CLEANING"))
                .contains(grill.getId())
                .doesNotContain(press.getId(), cleaners.getId());
        assertThat(candidates("SERVICES", "PRINTING")).containsExactly(press.getId());
        assertThat(candidates("SERVICES", "")).isEmpty();
        assertThat(candidates("RESTAURANT", "")).contains(grill.getId())
                .doesNotContain(press.getId(), cleaners.getId());
    }

    @Test
    @DisplayName("the district chips come from goods shops only")
    void district_chips_come_from_goods_shops_only() {
        assertThat(stores.distinctNeighborhoods())
                .contains("Hamra")
                .doesNotContain("Print Quarter");
    }

    @Test
    @DisplayName("the catalogue never lists a service offer, and its count agrees")
    void the_catalogue_never_lists_a_service_offer() {
        Page<Product> everything = products.findActiveCatalog(null, "%", PageRequest.of(0, 1000));
        assertThat(everything.getContent()).extracting(Product::getName)
                .contains("Mixed grill platter")
                .doesNotContain("500 business cards");
        assertThat(products.findActiveCatalog(null, "%business cards%", PageRequest.of(0, 5))
                .getTotalElements()).isZero();
    }

    /**
     * Home's "Your favourites" rail, which every installed app draws. The customer starred a goods
     * shop, an open service shop and one in a closed category; Home lists only the goods shop, so the
     * print shop is not drawn there as a restaurant and the cleaners are not shown at all. The stars
     * themselves are kept: only the listing leaves the service shops out.
     */
    @Test
    @DisplayName("Home's favourites never list a service shop, and every star is kept")
    void home_favourites_never_list_a_service_shop() {
        assertThat(stores.findFavoritesOf("customer-it", PageRequest.of(0, 20)).getContent())
                .extracting(Store::getName)
                .containsExactly("Hamra Kebab Corner");
        assertThat(service.favoritesOf("customer-it", PageRequest.of(0, 20)).getContent().stream()
                .map(view -> view.store().getName()).toList())
                .containsExactly("Hamra Kebab Corner");

        assertThat(repositories.getRepository(StoreFavoriteRepository.class)
                .findStoreIdsByUserId("customer-it"))
                .containsExactlyInAnyOrder(grill.getId(), press.getId(), cleaners.getId());
    }

    // ------------------------------------------------------------------------------------ helpers

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
        // Not the service's hibernate.jdbc.time_zone=UTC. The pods run in UTC, where that setting
        // changes nothing; on a machine in another zone it shifts every LocalTime by the JVM's offset,
        // so opening hours of 00:00-23:59 were written as 22:00-21:59 and refused by chk_hours_order.
        // That offset belongs to the machine running the test, not to the code under test.
        // Spring Boot's naming, so a column an entity leaves implicit is looked for where the app looks.
        jpa.put("hibernate.physical_naming_strategy",
                "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy");
        jpa.put("hibernate.implicit_naming_strategy",
                "org.springframework.boot.orm.jpa.hibernate.SpringImplicitNamingStrategy");
        factory.setJpaPropertyMap(jpa);
        factory.afterPropertiesSet();
        return factory.getObject();
    }

    private StoreService storeService(MockEnvironment environment) {
        return new StoreService(stores, repositories.getRepository(StoreOfferRepository.class),
                repositories.getRepository(StoreFavoriteRepository.class), products,
                repositories.getRepository(CategoryRepository.class),
                new ServiceCategories(environment),
                org.mockito.Mockito.mock(
                        com.delivery.product.service.OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4), "Asia/Beirut");
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

    private void execute(String sql) throws SQLException {
        try (Connection connection = connection(); Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    /** A shop as the schema before V33 holds it, written with the columns that schema has. */
    private void insertGoodsShop(String name, String vertical, double latitude, double longitude,
                                 String district) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO stores (id, merchant_id, name, slug, vertical, status, latitude, "
                             + "longitude, neighborhood, published_at) "
                             + "VALUES (?, 'merchant-it', ?, ?, ?, 'ACTIVE', ?, ?, ?, now())")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setString(2, name);
            insert.setString(3, "it-" + id);
            insert.setString(4, vertical);
            insert.setBigDecimal(5, BigDecimal.valueOf(latitude));
            insert.setBigDecimal(6, BigDecimal.valueOf(longitude));
            insert.setString(7, district);
            insert.executeUpdate();
        }
    }

    private void insertRawShop(String vertical, String category) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO stores (id, merchant_id, name, slug, vertical, service_category) "
                             + "VALUES (?, 'merchant-it', 'Refused', ?, ?, ?)")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setString(2, "refused-" + id);
            insert.setString(3, vertical);
            insert.setString(4, category);
            insert.executeUpdate();
        }
    }

    private UUID firstPlatformCategory() throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(
                     "SELECT id FROM categories WHERE store_id IS NULL ORDER BY name LIMIT 1")) {
            return rows.next() ? rows.getObject(1, UUID.class) : null;
        }
    }

    /** Listed, pinned and open all week, in a district no goods shop declares. */
    private static Store listedAt(Store store, double latitude, double longitude) {
        store.pinAt(GeoPoint.of(latitude, longitude));
        store.setNeighborhood("Print Quarter");
        store.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        store.publish(NOW.minus(Duration.ofDays(30)));
        return store;
    }

    private static Product liveProduct(Store shop, String name, UUID aisle) {
        Product product = new Product(shop.getMerchantId(), shop.getId(), name, null,
                new BigDecimal("16.00"), aisle);
        product.addImage("products/" + UUID.randomUUID() + ".jpg");
        product.publish();
        return product;
    }

    private static NearbyFilters asking(Store.Vertical vertical, Store.ServiceCategory category) {
        return new NearbyFilters(false, null, null, null, false, vertical, category);
    }

    private static List<String> storefrontNames(StoreService from, Store.Vertical vertical,
                                                Store.ServiceCategory category, String search) {
        return from.storefront(vertical, category, search, null, null, null, null,
                        PageRequest.of(0, 500))
                .getContent().stream().map(view -> view.store().getName()).toList();
    }

    private static List<String> nearbyNames(StoreService from, NearbyFilters filters) {
        return from.nearby(HAMRA, 5_000, 500, filters, PageRequest.of(0, 200)).page()
                .getContent().stream().map(near -> near.store().store().getName()).toList();
    }

    private List<UUID> candidates(String vertical, String categories) {
        return stores.findActiveIdsNear(HAMRA.latitude().doubleValue(),
                HAMRA.longitude().doubleValue(), 5_000, "", NOW, "", false, false, NOW, vertical,
                categories, 200);
    }
}
