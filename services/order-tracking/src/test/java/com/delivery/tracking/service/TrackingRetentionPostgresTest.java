package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

/**
 * The tracking schema and its retention job on a real Postgres with PostGIS.
 *
 * <p>The rollup is SQL the rest of the suite can only read as text, and the migrations only run
 * against a database. This applies every tracking migration with Flyway — V17 shared with the
 * checkout map, V18 making the rollup's coordinates optional — and runs the retention job over a
 * day past the window.
 *
 * <p>Only runs when {@code TRACKING_IT_DB_URL} names a throwaway database (user and password from
 * {@code TRACKING_IT_DB_USER} / {@code TRACKING_IT_DB_PASSWORD}, default {@code postgres}): it
 * drops and recreates the {@code tracking} schema. For example, with
 * {@code docker run -d --name tracking-it -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=delivery
 * -p 55871:5432 postgis/postgis:17-3.5}, {@code TRACKING_IT_DB_URL=jdbc:postgresql://localhost:55871/delivery}.
 */
@EnabledIfEnvironmentVariable(named = "TRACKING_IT_DB_URL", matches = ".+")
@DisplayName("the tracking schema and its retention job, on a real Postgres")
class TrackingRetentionPostgresTest {

    private static final DateTimeFormatter SUFFIX = DateTimeFormatter.ofPattern("yyyyMMdd");

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

        jdbc = new JdbcTemplate(new DriverManagerDataSource(
                url + (url.contains("?") ? "&" : "?") + "currentSchema=tracking", user, password));
    }

    private static void ping(UUID order, double lat, double lng, Instant at) {
        jdbc.update("INSERT INTO tracking_events (id, order_id, rider_id, lat, lng, accuracy_m, "
                        + "recorded_at) VALUES (?, ?, 'rider-sub', ?, ?, 6, ?)",
                UUID.randomUUID(), order, lat, lng, Timestamp.from(at));
    }

    @Test
    @DisplayName("every migration applies, with V17's columns and V18's optional coordinates")
    void every_migration_applies() {
        Integer latest = jdbc.queryForObject(
                "SELECT max(version::int) FROM flyway_schema_history WHERE success", Integer.class);
        assertThat(latest).isEqualTo(18);

        assertThat(jdbc.queryForList("""
                SELECT column_name FROM information_schema.columns
                 WHERE table_schema = 'tracking' AND table_name = 'order_participants'
                   AND column_name IN ('checkout_id', 'store_name', 'picked_up_at', 'completed_at')
                """, String.class)).hasSize(4);

        assertThat(jdbc.queryForList("""
                SELECT column_name FROM information_schema.columns
                 WHERE table_schema = 'tracking' AND table_name = 'tracking_event_rollup'
                   AND column_name IN ('first_lat', 'first_lng', 'last_lat', 'last_lng')
                   AND is_nullable = 'YES'
                """, String.class))
                .containsExactlyInAnyOrder("first_lat", "first_lng", "last_lat", "last_lng");
    }

    @Test
    @DisplayName("a day past retention is summarised with no position, then dropped; older "
            + "summaries are left as they were")
    void a_day_past_retention_keeps_no_position() {
        LocalDate day = LocalDate.now().minusDays(40);
        String partition = "tracking_events_" + day.format(SUFFIX);
        jdbc.execute("CREATE TABLE IF NOT EXISTS " + partition + " PARTITION OF tracking_events "
                + "FOR VALUES FROM ('" + day + "') TO ('" + day.plusDays(1) + "')");

        // A delivery from the shop to a door about 820 m away, over twenty minutes.
        UUID order = UUID.randomUUID();
        Instant start = day.atTime(10, 0).toInstant(ZoneOffset.UTC);
        ping(order, 33.8938, 35.5018, start);
        ping(order, 33.8912, 35.4990, start.plusSeconds(600));
        ping(order, 33.8886, 35.4955, start.plusSeconds(1200));

        // A summary written before this change, with its coordinates: it must survive untouched.
        UUID earlier = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO tracking_event_rollup (order_id, day, ping_count, first_seen_at,
                    last_seen_at, first_lat, first_lng, last_lat, last_lng, span_metres)
                VALUES (?, ?, 2, ?, ?, 51.5074, -0.1278, 51.5080, -0.1270, 90)
                """, earlier, java.sql.Date.valueOf(day.minusDays(1)),
                Timestamp.from(start.minusSeconds(86_400)),
                Timestamp.from(start.minusSeconds(86_000)));

        TrackingPartitionMaintenance maintenance =
                new TrackingPartitionMaintenance(jdbc, 30, 7, 400);
        // Directly first, so an SQL error surfaces here rather than in the job's own log line.
        assertThat(maintenance.rollUpExpired()).isGreaterThanOrEqualTo(1);
        maintenance.run();

        Map<String, Object> summary = jdbc.queryForMap(
                "SELECT * FROM tracking_event_rollup WHERE order_id = ?", order);
        assertThat(((Number) summary.get("ping_count")).intValue()).isEqualTo(3);
        assertThat(((Timestamp) summary.get("first_seen_at")).toInstant()).isEqualTo(start);
        assertThat(((Timestamp) summary.get("last_seen_at")).toInstant())
                .isEqualTo(start.plusSeconds(1200));
        for (String coordinate : List.of("first_lat", "first_lng", "last_lat", "last_lng")) {
            assertThat(summary.get(coordinate)).as(coordinate).isNull();
        }
        assertThat(((Number) summary.get("span_metres")).doubleValue()).isCloseTo(820, within(40d));

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM pg_class WHERE relname = ?", Integer.class, partition))
                .as("the expired day's partition").isZero();

        Map<String, Object> kept = jdbc.queryForMap(
                "SELECT * FROM tracking_event_rollup WHERE order_id = ?", earlier);
        assertThat(((Number) kept.get("first_lat")).doubleValue()).isEqualTo(51.5074);

        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM tracking_event_rollup
                 WHERE 'NaN' IN (first_lat, first_lng, last_lat, last_lng)
                """, Integer.class)).as("no NaN anywhere in the table").isZero();
    }
}
