package com.delivery.product.domain;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.product.domain.PhotoSearchUse.Kind;
import com.delivery.product.service.PhotoQuota;
import com.delivery.product.service.PhotoSearchException;
import com.delivery.product.service.PhotoSearchException.Scope;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Photo search's SQL, against a real PostgreSQL: V38 and the quota — the counts, the windows, the
 * sweep, and the advisory lock that stops two photos sent at once from both taking the last one — and
 * the merchant's find by photo, which matches a photo's words against one merchant's own products in
 * every status ({@link ProductFindRepository}).
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, as
 * {@code ItemSearchDatabaseTest} does, and CI runs it the same way. It migrates a schema of its own
 * with a random name and drops only that schema. {@link PhotoQuota#take} is transactional in the
 * service; here each call runs in a transaction the test opens, as Spring's would.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("photo search, against a real database")
class PhotoSearchDatabaseTest {

    /** A real EAN-13, as ItemSearchDatabaseTest uses. */
    private static final String EAN = "5449000000996";

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "photo_search_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private PhotoSearchUseRepository uses;
    private ProductFindRepository finder;

    /** One merchant's two shops, and a rival's, with the products the find tests look for. */
    private Store grocer;
    private Store kiosk;
    private Store rival;
    private Product byCode;
    private Product draft;
    private Product archived;
    private Product inTheKiosk;
    private Product rivals;
    private final MovableClock clock = new MovableClock(Instant.parse("2026-09-20T10:00:00Z"));

    /**
     * The configured limits: ten a day, three a minute, a thousand for the customers' platform day,
     * thirty for a merchant, five hundred for the merchants' platform day.
     */
    private static final PhotoQuota.Limits CONFIGURED = new PhotoQuota.Limits(10, 3, 1000, 30, 500);

    /** The limits in force; the platform tests lower a platform day to five to reach it. */
    private PhotoQuota.Limits limits = CONFIGURED;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    /** A clock the test moves by hand. */
    private static final class MovableClock extends Clock {
        private volatile Instant now;

        MovableClock(Instant now) {
            this.now = now;
        }

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    @BeforeAll
    void migrateFromEmpty() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
            statement.execute("CREATE SCHEMA " + schema);
        }
        Flyway.configure()
                .dataSource(url, user, password)
                .schemas(schema)
                .defaultSchema(schema)
                .locations("classpath:db/migration/shared", "classpath:db/migration/product")
                .outOfOrder(true)
                .load()
                .migrate();

        entityManagerFactory = entityManagerFactory();
        em = entityManagerFactory.createEntityManager();
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(em);
        uses = repositories.getRepository(PhotoSearchUseRepository.class);
        finder = repositories.getRepository(ProductFindRepository.class);
        seedTheCatalogue();
    }

    /**
     * One merchant with two shops and a rival with one, and a handful of products across them — in
     * every status, with an Arabic name and a barcode, so the find query can be asked what it keeps.
     */
    private void seedTheCatalogue() {
        em.getTransaction().begin();
        grocer = new Store("merchant-find", "Find Grocer", Store.Vertical.GROCERY);
        kiosk = new Store("merchant-find", "Find Kiosk", Store.Vertical.GROCERY);
        rival = new Store("merchant-rival", "Rival Grocer", Store.Vertical.GROCERY);
        for (Store store : List.of(grocer, kiosk, rival)) {
            em.persist(store);
        }
        // Named nothing like the photo, so only its barcode can find it.
        byCode = product(grocer, "Fizzy drink, large bottle");
        byCode.assignCodes(null, EAN);
        draft = product(grocer, "Pepsi 1L");
        archived = product(grocer, "بيبسي 2 لتر");
        archived.archive();
        inTheKiosk = product(kiosk, "Pepsi 1L kiosk stock");
        rivals = product(rival, "Pepsi 1L");
        for (int i = 0; i < 6; i++) {
            product(grocer, "Pepsi 1L variant " + i);
        }
        em.getTransaction().commit();
        em.clear();
    }

    private Product product(Store store, String name) {
        Product product = new Product(store.getMerchantId(), store.getId(), name, null,
                new BigDecimal("1.25"), null);
        em.persist(product);
        return product;
    }

    @AfterAll
    void dropTheSchema() throws SQLException {
        if (em != null) {
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
            statement.execute("SET lock_timeout = '30s'");
            statement.execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
        }
    }

    @BeforeEach
    void emptyTheTable() throws SQLException {
        limits = CONFIGURED;
        try (Connection connection = DriverManager.getConnection(urlInSchema(), user, password);
             Statement statement = connection.createStatement()) {
            statement.execute("DELETE FROM photo_search_uses");
        }
    }

    /** One use, in its own transaction, as the service's {@code @Transactional} runs it. */
    private int take(String account, Kind kind) {
        return take(em, account, kind);
    }

    private int take(EntityManager manager, String account, Kind kind) {
        PhotoQuota quota = new PhotoQuota(new JpaRepositoryFactory(manager)
                .getRepository(PhotoSearchUseRepository.class), clock, limits);
        manager.getTransaction().begin();
        try {
            int left = quota.take(account, kind);
            manager.getTransaction().commit();
            return left;
        } catch (RuntimeException e) {
            manager.getTransaction().rollback();
            throw e;
        }
    }

    private long stored(String account) {
        em.clear();
        return uses.countByAccountIdAndKindAndCreatedAtAfter(account, Kind.CUSTOMER_SEARCH, Instant.EPOCH)
                + uses.countByAccountIdAndKindAndCreatedAtAfter(account, Kind.MERCHANT_FIND, Instant.EPOCH);
    }

    @Test
    @DisplayName("the table takes only the two kinds, and nothing about the photo")
    void the_table_takes_only_the_two_kinds() throws SQLException {
        try (Connection connection = DriverManager.getConnection(urlInSchema(), user, password);
             Statement statement = connection.createStatement()) {
            assertThatThrownBy(() -> statement.execute("INSERT INTO photo_search_uses (id, account_id, kind) "
                    + "VALUES ('" + UUID.randomUUID() + "', 'someone', 'PHOTO_UPLOAD')"))
                    .isInstanceOf(SQLException.class)
                    .hasMessageContaining("chk_photo_search_use_kind");
            var columns = statement.executeQuery("SELECT string_agg(column_name, ',' ORDER BY column_name) "
                    + "FROM information_schema.columns WHERE table_schema = '" + schema
                    + "' AND table_name = 'photo_search_uses'");
            columns.next();
            assertThat(columns.getString(1)).isEqualTo("account_id,created_at,id,kind");
        }
    }

    @Test
    @DisplayName("a customer has ten a day, and the eleventh is told to wait until the oldest leaves the day")
    void ten_a_day() {
        Instant first = clock.instant();
        for (int i = 0; i < 10; i++) {
            assertThat(take("customer-day", Kind.CUSTOMER_SEARCH)).isEqualTo(9 - i);
            clock.advance(Duration.ofSeconds(61));
        }

        assertThatThrownBy(() -> take("customer-day", Kind.CUSTOMER_SEARCH))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.getCode()).isEqualTo("PHOTO_SEARCH_LIMIT");
                    assertThat(e.getScope()).isEqualTo(Scope.DAY);
                    assertThat(e.getLimit()).isEqualTo(10);
                    long expected = Duration.between(clock.instant(), first.plus(Duration.ofHours(24))).getSeconds();
                    assertThat(e.getRetryAfterSeconds()).isEqualTo(expected);
                });
        // A refused use is not counted.
        assertThat(stored("customer-day")).isEqualTo(10);

        // The first one leaves the day, and one more is allowed.
        clock.advance(Duration.between(clock.instant(), first.plus(Duration.ofHours(24))).plusSeconds(1));
        assertThat(take("customer-day", Kind.CUSTOMER_SEARCH)).isZero();
    }

    @Test
    @DisplayName("three a minute, then a wait of at most a minute")
    void three_a_minute() {
        for (int i = 0; i < 3; i++) {
            take("customer-burst", Kind.CUSTOMER_SEARCH);
            clock.advance(Duration.ofSeconds(5));
        }

        assertThatThrownBy(() -> take("customer-burst", Kind.CUSTOMER_SEARCH))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.getScope()).isEqualTo(Scope.MINUTE);
                    assertThat(e.getLimit()).isEqualTo(3);
                    assertThat(e.getRetryAfterSeconds()).isBetween(1L, 60L);
                });

        clock.advance(Duration.ofSeconds(50));
        assertThat(take("customer-burst", Kind.CUSTOMER_SEARCH)).isEqualTo(6);
    }

    @Test
    @DisplayName("the platform's day counts every customer, and merchants' finds are not in it")
    void the_platform_day_counts_every_customer() {
        limits = new PhotoQuota.Limits(10, 3, 5, 30, 500);
        for (int i = 0; i < 40; i++) {
            take("merchant-" + i, Kind.MERCHANT_FIND);
        }
        for (int i = 0; i < 5; i++) {
            take("customer-" + i, Kind.CUSTOMER_SEARCH);
        }

        assertThatThrownBy(() -> take("customer-new", Kind.CUSTOMER_SEARCH))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.getCode()).isEqualTo("PHOTO_SEARCH_LIMIT");
                    assertThat(e.getScope()).isEqualTo(Scope.PLATFORM);
                    assertThat(e.getLimit()).isEqualTo(5);
                });
        // Merchants are not held to the customers' platform day: they have one of their own.
        assertThat(take("merchant-more", Kind.MERCHANT_FIND)).isEqualTo(29);
    }

    /**
     * The other half of the cap above. A find by photo is the same paid call as a search, so with no
     * platform day of their own a hundred merchants at thirty finds each would be three thousand calls
     * a day that nothing refused.
     */
    @Test
    @DisplayName("the merchants have a platform day of their own, which customers neither spend nor share")
    void the_platform_day_counts_every_merchant() {
        limits = new PhotoQuota.Limits(10, 3, 1000, 30, 5);
        for (int i = 0; i < 20; i++) {
            take("shopper-" + i, Kind.CUSTOMER_SEARCH);
        }
        for (int i = 0; i < 5; i++) {
            take("shop-" + i, Kind.MERCHANT_FIND);
        }

        assertThatThrownBy(() -> take("shop-new", Kind.MERCHANT_FIND))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    // The merchant's own code, and the scope that says it is the platform rather than
                    // this shop that has had enough today.
                    assertThat(e.getCode()).isEqualTo("PHOTO_FIND_LIMIT");
                    assertThat(e.getScope()).isEqualTo(Scope.PLATFORM);
                    assertThat(e.getLimit()).isEqualTo(5);
                    assertThat(e.getRetryAfterSeconds()).isNotNull();
                });
        // Refused, so not counted; and the customers' own day is untouched by any of it.
        assertThat(stored("shop-new")).isZero();
        assertThat(take("shopper-new", Kind.CUSTOMER_SEARCH)).isEqualTo(9);
    }

    @Test
    @DisplayName("a merchant's finds and a customer's searches are counted apart, with limits of their own")
    void kinds_are_counted_apart() {
        for (int i = 0; i < 10; i++) {
            take("both", Kind.CUSTOMER_SEARCH);
            clock.advance(Duration.ofSeconds(61));
        }
        assertThat(take("both", Kind.MERCHANT_FIND)).isEqualTo(29);

        assertThatThrownBy(() -> {
            for (int i = 0; i < 3; i++) {
                take("finder", Kind.MERCHANT_FIND);
            }
            take("finder", Kind.MERCHANT_FIND);
        }).isInstanceOfSatisfying(PhotoSearchException.class, e -> {
            assertThat(e.getCode()).isEqualTo("PHOTO_FIND_LIMIT");
            assertThat(e.getScope()).isEqualTo(Scope.MINUTE);
        });
    }

    @Test
    @DisplayName("a use older than 48 hours is deleted by the next one, whoever's it is")
    void old_uses_are_swept() {
        take("old-customer", Kind.CUSTOMER_SEARCH);
        clock.advance(Duration.ofHours(49));

        take("someone-else", Kind.CUSTOMER_SEARCH);

        assertThat(stored("old-customer")).isZero();
        assertThat(stored("someone-else")).isEqualTo(1);
    }

    @Test
    @DisplayName("what is left is read without counting")
    void left_does_not_count() {
        take("reader", Kind.CUSTOMER_SEARCH);
        PhotoQuota quota = new PhotoQuota(uses, clock, limits);

        assertThat(quota.left("reader", Kind.CUSTOMER_SEARCH)).isEqualTo(9);
        assertThat(quota.left("reader", Kind.CUSTOMER_SEARCH)).isEqualTo(9);
        assertThat(quota.left("reader", Kind.MERCHANT_FIND)).isEqualTo(30);
    }

    /**
     * Two photos from one account with one use left: the second waits on the account's lock until the
     * first commits, then counts it, and is refused. Without the lock both would count nine and both
     * would take the tenth.
     */
    @Test
    @DisplayName("two photos at once cannot both take the account's last use")
    void the_account_lock_serialises_the_last_use() throws Exception {
        for (int i = 0; i < 9; i++) {
            take("racer", Kind.CUSTOMER_SEARCH);
            clock.advance(Duration.ofSeconds(61));
        }

        EntityManager first = entityManagerFactory.createEntityManager();
        EntityManager second = entityManagerFactory.createEntityManager();
        try {
            PhotoQuota firstQuota = new PhotoQuota(new JpaRepositoryFactory(first)
                    .getRepository(PhotoSearchUseRepository.class), clock, limits);
            // The first takes the last use and holds its transaction open.
            first.getTransaction().begin();
            assertThat(firstQuota.take("racer", Kind.CUSTOMER_SEARCH)).isZero();

            CountDownLatch started = new CountDownLatch(1);
            CompletableFuture<Object> racing = CompletableFuture.supplyAsync(() -> {
                started.countDown();
                try {
                    return take(second, "racer", Kind.CUSTOMER_SEARCH);
                } catch (PhotoSearchException e) {
                    return e;
                }
            });
            assertThat(started.await(10, TimeUnit.SECONDS)).isTrue();
            // Still waiting on the lock the first holds.
            Thread.sleep(500);
            assertThat(racing).isNotDone();

            first.getTransaction().commit();
            Object outcome = racing.get(30, TimeUnit.SECONDS);
            assertThat(outcome).isInstanceOfSatisfying(PhotoSearchException.class,
                    e -> assertThat(e.getScope()).isEqualTo(Scope.DAY));
            assertThat(stored("racer")).isEqualTo(10);
        } finally {
            if (first.getTransaction().isActive()) {
                first.getTransaction().rollback();
            }
            first.close();
            second.close();
        }
    }

    // ------------------------------------------------------------------ the merchant's own catalogue

    /** The find as the service asks it: the photo's three words, its barcode, and the shops to look in. */
    private List<ProductFindRepository.Found> find(List<UUID> shopIds, String name, String nameAr,
                                                   String brand, String barcode, int maxRows) {
        return finder.findInStores(shopIds,
                name, name, nameAr, nameAr, brand, brand, barcode, maxRows);
    }

    @Test
    @DisplayName("a product whose barcode is equal comes first, whatever it is called")
    void the_barcode_match_comes_first() {
        List<ProductFindRepository.Found> found =
                find(List.of(grocer.getId()), "pepsi 1l", "", "pepsi", EAN, 5);

        assertThat(found).isNotEmpty();
        assertThat(found.get(0).productId()).isEqualTo(byCode.getId());
        assertThat(found.get(0).tier()).isZero();
        assertThat(found.stream().skip(1)).allSatisfy(row -> assertThat(row.tier()).isPositive());
    }

    @Test
    @DisplayName("every status is searched: a draft and an archived product are both matches")
    void every_status_is_searched() {
        List<UUID> shops = List.of(grocer.getId());

        assertThat(find(shops, "pepsi 1l", "", "", "", 20))
                .extracting(ProductFindRepository.Found::productId)
                .contains(draft.getId());
        // The Arabic name matches the Arabic words, and being archived does not hide it.
        assertThat(find(shops, "", "بيبسي", "", "", 20))
                .extracting(ProductFindRepository.Found::productId)
                .contains(archived.getId());
    }

    @Test
    @DisplayName("only the shops asked about are searched, never another merchant's")
    void only_the_shops_asked_about() {
        List<ProductFindRepository.Found> mine =
                find(List.of(grocer.getId(), kiosk.getId()), "pepsi 1l", "", "", "", 50);

        assertThat(mine).extracting(ProductFindRepository.Found::productId)
                .contains(inTheKiosk.getId())
                .doesNotContain(rivals.getId());
        assertThat(mine).extracting(ProductFindRepository.Found::storeId)
                .doesNotContain(rival.getId());
    }

    @Test
    @DisplayName("at most the rows asked for come back, best first")
    void the_cap_keeps_the_best() {
        List<ProductFindRepository.Found> found =
                find(List.of(grocer.getId()), "pepsi 1l", "", "", EAN, 5);

        assertThat(found).hasSize(5);
        assertThat(found).isSortedAccordingTo((a, b) -> {
            int byTier = Integer.compare(a.tier(), b.tier());
            return byTier != 0 ? byTier : Double.compare(b.score(), a.score());
        });
    }

    @Test
    @DisplayName("a photo with no words and no barcode matches nothing at all")
    void nothing_to_match_matches_nothing() {
        assertThat(find(List.of(grocer.getId()), "", "", "", "", 5)).isEmpty();
    }

    @Test
    @DisplayName("a barcode is taken when one of these shops already carries it, and not by a rival's")
    void barcode_taken_is_scoped_to_the_shops() {
        assertThat(finder.barcodeTaken(List.of(grocer.getId()), EAN)).isTrue();
        assertThat(finder.barcodeTaken(List.of(kiosk.getId()), EAN)).isFalse();
        assertThat(finder.barcodeTaken(List.of(grocer.getId()), "96385074")).isFalse();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it — PhotoSearchUse against V38 included.
        jpa.put("hibernate.hbm2ddl.auto", "validate");
        jpa.put("hibernate.default_schema", schema);
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
}
