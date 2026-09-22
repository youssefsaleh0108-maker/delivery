package com.delivery.product.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.SharedEntityManagerCreator;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * {@code menu_view_day} against a real database: what it may hold, and that adding into it works.
 *
 * <p>The first test is the privacy promise stated as a fact about the schema rather than as prose
 * in a migration. V44's argument is that this table cannot be used to follow a reader because there
 * is nothing in it to follow — no visit, no timestamp, no identifier — and the only way to keep
 * that true is to fail the build when a column appears that would make it false.
 *
 * <p>Run the same way {@code SearchDemandDatabaseTest} is: a schema of its own with a random name,
 * migrated by the real Flyway from empty, with Hibernate in {@code validate} so an entity that has
 * drifted from V44 cannot start. Skipped without {@code PRODUCT_TEST_DB_URL}; CI supplies one and
 * fails the build if this was skipped.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("the menu-view counters")
class MenuViewDatabaseTest {

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "menu_views_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private TransactionTemplate tx;
    private MenuViewDayRepository days;
    private StoreRepository stores;

    private UUID shopId;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
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
        EntityManager shared =
                SharedEntityManagerCreator.createSharedEntityManager(entityManagerFactory);
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(shared);
        days = repositories.getRepository(MenuViewDayRepository.class);
        stores = repositories.getRepository(StoreRepository.class);
        tx = new TransactionTemplate(new JpaTransactionManager(entityManagerFactory));

        tx.executeWithoutResult(status -> {
            Store shop = new Store("merchant-sub", "Boulangerie Antoine", Store.Vertical.GROCERY);
            shopId = stores.save(shop).getId();
        });
    }

    @BeforeEach
    void emptyTheTable() {
        tx.executeWithoutResult(status -> days.deleteAllInBatch());
    }

    @AfterAll
    void dropTheSchema() throws SQLException {
        if (entityManagerFactory != null) {
            entityManagerFactory.close();
        }
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            statement.execute("SET lock_timeout = '30s'");
            statement.execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
        }
    }

    // ------------------------------------------------------------------- what the table may hold

    @Test
    @DisplayName("has exactly these columns, and none that could follow a reader")
    void holds_nothing_personal() throws SQLException {
        assertThat(columnsOf("menu_view_day")).containsExactlyInAnyOrder(
                "store_id", "viewed_on", "day_part", "source", "views");

        // Spelled out again as the absences they are, so the reason survives a rename. Note
        // `searched_at` has no equivalent here at all: V40 keeps a truncated hour because it must
        // keep one row per search; this table keeps counters, so it keeps no time of any kind
        // beyond which quarter of the shop's day.
        assertThat(columnsOf("menu_view_day")).doesNotContain(
                "account_id", "customer_id", "user_id", "session_id", "device_id", "request_id",
                "ip", "ip_address", "user_agent", "referrer", "latitude", "longitude", "location",
                "viewed_at", "opened_at", "created_at", "hour", "minute", "country", "language",
                "table_number", "id");
    }

    @Test
    @DisplayName("the day is a date, so there is no time of day hiding in it")
    void the_day_is_a_date() throws SQLException {
        assertThat(typeOf("menu_view_day", "viewed_on")).isEqualTo("date");
    }

    @Test
    @DisplayName("there is no surrogate key, because a surrogate key would be a sequence")
    void the_key_is_the_bucket() throws SQLException {
        List<String> key = primaryKeyOf("menu_view_day");

        // The counter's identity is the bucket itself. A bigserial would order the rows, and the
        // order rows were written in is the one thing a table of counters must not acquire.
        assertThat(key).containsExactlyInAnyOrder("store_id", "viewed_on", "day_part", "source");
    }

    @Test
    @DisplayName("only the four parts of the day and the two ways in are accepted")
    void the_check_constraints_hold() {
        assertThatThrownBy(() -> tx.executeWithoutResult(status ->
                days.add(shopId, LocalDate.of(2026, 9, 22), "TEATIME", "LINK", 1)))
                .isInstanceOf(Exception.class);

        // "QR" is not a source, and the constraint is where that is enforced rather than only in
        // an enum: the shop's counter code carries no marker, so a QR row could only be a guess.
        assertThatThrownBy(() -> tx.executeWithoutResult(status ->
                days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "QR", 1)))
                .isInstanceOf(Exception.class);
    }

    // -------------------------------------------------------------------------- adding into it

    @Test
    @DisplayName("a second flush adds to the counter instead of replacing or doubling it")
    void adding_accumulates() {
        tx.executeWithoutResult(status ->
                days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "LINK", 12));
        tx.executeWithoutResult(status ->
                days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "LINK", 5));

        List<MenuViewDay> rows = tx.execute(status ->
                days.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(shopId,
                        LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 30)));

        // One row, seventeen views. Two pods flushing the same morning both land.
        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).getViews()).isEqualTo(17);
        assertThat(rows.get(0).getDayPart()).isEqualTo(MenuViewDay.Part.MORNING);
        assertThat(rows.get(0).getSource()).isEqualTo(MenuViewDay.Source.LINK);
    }

    @Test
    @DisplayName("the parts of the day and the ways in are counted apart")
    void buckets_do_not_mix() {
        tx.executeWithoutResult(status -> {
            days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "LINK", 3);
            days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "TABLE", 4);
            days.add(shopId, LocalDate.of(2026, 9, 22), "EVENING", "LINK", 5);
            days.add(shopId, LocalDate.of(2026, 9, 23), "MORNING", "LINK", 6);
        });

        List<MenuViewDay> rows = tx.execute(status ->
                days.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(shopId,
                        LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 30)));

        assertThat(rows).hasSize(4);
        assertThat(rows.stream().mapToInt(MenuViewDay::getViews).sum()).isEqualTo(18);
    }

    @Test
    @DisplayName("the window is the window asked for, at both ends")
    void the_window_is_inclusive() {
        tx.executeWithoutResult(status -> {
            days.add(shopId, LocalDate.of(2026, 9, 15), "MORNING", "LINK", 1);
            days.add(shopId, LocalDate.of(2026, 9, 16), "MORNING", "LINK", 2);
            days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "LINK", 4);
            days.add(shopId, LocalDate.of(2026, 9, 23), "MORNING", "LINK", 8);
        });

        List<MenuViewDay> rows = tx.execute(status ->
                days.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(shopId,
                        LocalDate.of(2026, 9, 16), LocalDate.of(2026, 9, 22)));

        // Both ends are days the merchant picked, so both are in.
        assertThat(rows.stream().mapToInt(MenuViewDay::getViews).sum()).isEqualTo(6);
    }

    @Test
    @DisplayName("retention forgets only the old")
    void retention_deletes_only_the_old() {
        tx.executeWithoutResult(status -> {
            days.add(shopId, LocalDate.of(2026, 1, 1), "MORNING", "LINK", 1);
            days.add(shopId, LocalDate.of(2026, 9, 22), "MORNING", "LINK", 2);
        });

        int gone = tx.execute(status -> days.deleteOlderThan(LocalDate.of(2026, 6, 1)));

        assertThat(gone).isEqualTo(1);
        List<MenuViewDay> left = tx.execute(status ->
                days.findByStoreIdAndViewedOnBetweenOrderByViewedOnAsc(shopId,
                        LocalDate.of(2025, 1, 1), LocalDate.of(2027, 1, 1)));
        assertThat(left).hasSize(1);
        assertThat(left.get(0).getViewedOn()).isEqualTo(LocalDate.of(2026, 9, 22));
    }

    // ------------------------------------------------------------------------------- plumbing

    private List<String> columnsOf(String table) throws SQLException {
        return strings("SELECT column_name FROM information_schema.columns WHERE table_schema = '"
                + schema + "' AND table_name = '" + table + "'");
    }

    private String typeOf(String table, String column) throws SQLException {
        List<String> found =
                strings("SELECT data_type FROM information_schema.columns WHERE table_schema = '"
                        + schema + "' AND table_name = '" + table + "' AND column_name = '"
                        + column + "'");
        return found.isEmpty() ? null : found.get(0);
    }

    private List<String> primaryKeyOf(String table) throws SQLException {
        return strings("""
                SELECT c.column_name
                FROM information_schema.table_constraints t
                JOIN information_schema.key_column_usage c
                  ON c.constraint_name = t.constraint_name
                 AND c.table_schema = t.table_schema
                WHERE t.constraint_type = 'PRIMARY KEY'
                  AND t.table_schema = '""" + schema + "' AND t.table_name = '" + table + "'");
    }

    private List<String> strings(String sql) throws SQLException {
        List<String> values = new ArrayList<>();
        try (Connection connection = DriverManager.getConnection(urlInSchema(), user, password);
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            while (rows.next()) {
                values.add(rows.getString(1));
            }
        }
        return values;
    }

    private String urlInSchema() {
        return url + (url.contains("?") ? "&" : "?") + "currentSchema=" + schema;
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // Flyway owns the schema and Hibernate refuses to start if an entity has drifted from it.
        // That is what makes this an assertion about V44 rather than about MenuViewDay.
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
}
