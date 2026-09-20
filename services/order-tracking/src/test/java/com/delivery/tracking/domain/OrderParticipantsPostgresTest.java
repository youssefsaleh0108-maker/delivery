package com.delivery.tracking.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Properties;
import java.util.UUID;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

/**
 * The projection's queries against a real Postgres, running the SQL Hibernate actually writes.
 *
 * <p>These are the queries the checkout map's privacy rests on, and every one of them turns on a
 * null: "a live order that is not this checkout's" has to count an order placed alone, whose
 * checkout is null, and {@code <>} is never true against null; "another customer's door" has to
 * skip rows with no coordinates. A mock repository answers whatever the test tells it to, so it
 * cannot show any of that — the reviewer asked for this one against a database.
 *
 * <p>Only runs when {@code TRACKING_IT_DB_URL} names a throwaway database (user and password from
 * {@code TRACKING_IT_DB_USER} / {@code TRACKING_IT_DB_PASSWORD}, default {@code postgres}); it
 * drops and recreates the {@code tracking} schema. For example, with
 * {@code docker run -d --name tracking-it -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=delivery
 * -p 55871:5432 postgis/postgis:17-3.5}, {@code TRACKING_IT_DB_URL=jdbc:postgresql://localhost:55871/delivery}.
 */
@EnabledIfEnvironmentVariable(named = "TRACKING_IT_DB_URL", matches = ".+")
@DisplayName("the order projection's queries, on a real Postgres")
class OrderParticipantsPostgresTest {

    private static final UUID CHECKOUT = UUID.fromString("c4ec0000-0000-4000-8000-000000000010");
    private static final UUID OTHER_CHECKOUT =
            UUID.fromString("c4ec0000-0000-4000-8000-000000000011");
    private static final String RIDER = "rider-sub";
    private static final String OTHER_RIDER = "rider-other";
    private static final String CUSTOMER = "customer-sub";
    private static final String THEM = "customer-other";

    private static EntityManagerFactory factory;
    private static EntityManager entityManager;
    private static OrderParticipantsRepository participants;
    private static JdbcTemplate jdbc;

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    @BeforeAll
    static void migrate() {
        String url = System.getenv("TRACKING_IT_DB_URL");
        String user = env("TRACKING_IT_DB_USER", "postgres");
        String password = env("TRACKING_IT_DB_PASSWORD", "postgres");

        DriverManagerDataSource admin = new DriverManagerDataSource(url, user, password);
        JdbcTemplate adminJdbc = new JdbcTemplate(admin);
        adminJdbc.execute("CREATE EXTENSION IF NOT EXISTS postgis");
        adminJdbc.execute("DROP SCHEMA IF EXISTS tracking CASCADE");
        Flyway.configure()
                .dataSource(admin)
                .schemas("tracking")
                .defaultSchema("tracking")
                .locations("classpath:db/migration/tracking")
                .load()
                .migrate();

        DriverManagerDataSource dataSource = new DriverManagerDataSource(
                url + (url.contains("?") ? "&" : "?") + "currentSchema=tracking", user, password);
        jdbc = new JdbcTemplate(dataSource);

        // The service's own entities and settings, without a Spring context: the point is the SQL
        // Hibernate writes for these mappings, not the wiring around it.
        LocalContainerEntityManagerFactoryBean entityManagerFactory =
                new LocalContainerEntityManagerFactoryBean();
        entityManagerFactory.setDataSource(dataSource);
        entityManagerFactory.setPackagesToScan("com.delivery.tracking.domain");
        entityManagerFactory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Properties hibernate = new Properties();
        hibernate.setProperty("hibernate.default_schema", "tracking");
        hibernate.setProperty("hibernate.hbm2ddl.auto", "validate");
        hibernate.setProperty("hibernate.jdbc.time_zone", "UTC");
        entityManagerFactory.setJpaProperties(hibernate);
        entityManagerFactory.afterPropertiesSet();

        factory = entityManagerFactory.getObject();
        entityManager = factory.createEntityManager();
        participants = new JpaRepositoryFactory(entityManager)
                .getRepository(OrderParticipantsRepository.class);
    }

    @AfterAll
    static void close() {
        if (entityManager != null) {
            entityManager.close();
        }
        if (factory != null) {
            factory.close();
        }
    }

    @BeforeEach
    void emptyTheTable() {
        jdbc.update("DELETE FROM order_participants");
        entityManager.clear();
    }

    /**
     * A row as the projection writes it. Coordinates and times are nullable on purpose: half of
     * what these queries have to get right is what they do with the rows that have none.
     */
    private static UUID row(String customer, String rider, String status, UUID checkout,
                            Double dropoffLat, Double dropoffLng, Instant completedAt) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO order_participants (order_id, customer_id, merchant_id, rider_id,
                    status, checkout_id, dropoff_lat, dropoff_lng, completed_at, updated_at)
                VALUES (?, ?, 'merchant-sub', ?, ?, ?, ?, ?, ?, now())
                """, id, customer, rider, status, checkout, dropoffLat, dropoffLng,
                completedAt == null ? null : Timestamp.from(completedAt));
        return id;
    }

    @Nested
    @DisplayName("whether a rider has deliveries that are not this checkout's")
    class OrdersOutside {

        @Test
        @DisplayName("no, for a rider carrying only this checkout's orders")
        void only_this_checkouts_orders() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
            row(CUSTOMER, RIDER, "READY", CHECKOUT, null, null, null);

            assertThat(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).isFalse();
        }

        @Test
        @DisplayName("yes, for a live order of another checkout")
        void another_checkouts_order() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
            row(THEM, RIDER, "READY", OTHER_CHECKOUT, null, null, null);

            assertThat(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).isTrue();
        }

        /**
         * The null trap, and the reason this test exists: an order placed on its own has no
         * checkout, and {@code checkout_id <> :checkout} is never true of a null. Without the
         * explicit null test the commonest kind of other delivery — a single-shop order — would
         * count as none.
         */
        @Test
        @DisplayName("yes, for an order placed alone, which has no checkout at all")
        void an_order_with_no_checkout_counts() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
            row(THEM, RIDER, "PICKED_UP", null, null, null, null);

            assertThat(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).isTrue();
        }

        @Test
        @DisplayName("no, once the outside order is delivered or cancelled")
        void a_finished_outside_order_does_not_count() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
            row(THEM, RIDER, "DELIVERED", OTHER_CHECKOUT, null, null, Instant.now());
            row(THEM, RIDER, "CANCELLED", null, null, null, Instant.now());

            assertThat(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).isFalse();
        }

        @Test
        @DisplayName("no, for another rider's outside order")
        void another_riders_order_does_not_count() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
            row(THEM, OTHER_RIDER, "PICKED_UP", OTHER_CHECKOUT, null, null, null);

            assertThat(participants.riderHasOtherLiveOrders(RIDER, CHECKOUT)).isFalse();
        }
    }

    /** The doors the hand-over buffer measures against — the gate's query, on the same rows. */
    @Nested
    @DisplayName("another customer's doors in this rider's hands")
    class OtherDoors {

        private static final double LAT = 33.8981;
        private static final double LNG = 35.5214;

        @Test
        @DisplayName("finds a live one, and never the asking customer's own")
        void live_doors_of_other_customers_only() {
            row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, LAT, LNG, null);
            UUID theirs = row(THEM, RIDER, "PICKED_UP", OTHER_CHECKOUT, LAT + 0.01, LNG, null);

            List<OrderParticipants> doors = participants.otherCustomersDoors(RIDER, CUSTOMER,
                    Instant.now().minus(Duration.ofMinutes(30)));

            assertThat(doors).extracting(OrderParticipants::getOrderId).containsExactly(theirs);
        }

        @Test
        @DisplayName("skips a row with no coordinates, which is no door at all")
        void a_row_without_coordinates_is_no_door() {
            row(THEM, RIDER, "PICKED_UP", OTHER_CHECKOUT, null, null, null);
            row(THEM, RIDER, "PICKED_UP", OTHER_CHECKOUT, LAT, null, null);

            assertThat(participants.otherCustomersDoors(RIDER, CUSTOMER,
                    Instant.now().minus(Duration.ofMinutes(30)))).isEmpty();
        }

        @Test
        @DisplayName("keeps one finished inside the window and drops one finished before it")
        void the_window_decides_for_finished_orders() {
            Instant now = Instant.now();
            UUID recent = row(THEM, RIDER, "DELIVERED", OTHER_CHECKOUT, LAT, LNG,
                    now.minus(Duration.ofMinutes(5)));
            row(THEM, RIDER, "DELIVERED", OTHER_CHECKOUT, LAT, LNG,
                    now.minus(Duration.ofHours(2)));

            List<OrderParticipants> doors = participants.otherCustomersDoors(RIDER, CUSTOMER,
                    now.minus(Duration.ofMinutes(30)));

            assertThat(doors).extracting(OrderParticipants::getOrderId).containsExactly(recent);
        }
    }

    /**
     * The checkout's own rows, whoever placed them: the map is served only when every one of them
     * is the caller's, so a row of somebody else's under the same id has to come back.
     */
    @Test
    @DisplayName("returns every row of a checkout, including one that is somebody else's")
    void a_checkout_returns_all_of_its_rows() {
        row(CUSTOMER, RIDER, "PICKED_UP", CHECKOUT, null, null, null);
        row(THEM, RIDER, "READY", CHECKOUT, null, null, null);
        row(CUSTOMER, RIDER, "READY", OTHER_CHECKOUT, null, null, null);

        List<OrderParticipants> rows = participants.findByCheckoutId(CHECKOUT);

        assertThat(rows).hasSize(2)
                .extracting(OrderParticipants::getCustomerId)
                .containsExactlyInAnyOrder(CUSTOMER, THEM);
    }
}
