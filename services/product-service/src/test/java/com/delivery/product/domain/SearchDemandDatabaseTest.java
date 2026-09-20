package com.delivery.product.domain;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.product.service.CoarseAreas;
import com.delivery.product.service.DemandWeeks;
import com.delivery.product.service.SearchDemandRecorder;
import com.delivery.product.service.SearchDemandRecorder.Recording;
import com.delivery.product.service.SeenKeys;
import com.delivery.product.service.UnmetDemand;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * V40 and the demand digest's three tables, against a real PostgreSQL.
 *
 * <p>The first test here is the one that matters most, and it is not about behaviour: it reads
 * {@code information_schema} and asserts the <strong>exact set of columns</strong>
 * {@code search_demand_log} has. A privacy promise made in a comment is a promise until somebody adds
 * a column; a promise made as an assertion fails the build. So "no account id, no pin, no device, no
 * session" is checked as a fact about the schema rather than as a fact about today's writer.
 *
 * <p>The rest needs a database for reasons no mock can stand in for: the roll-up's floor is applied
 * in SQL {@code HAVING}, retention is a delete by a bound cutoff, the digest ledger's idempotency is
 * a unique constraint, and every entity is validated against the migration as the service validates
 * it at boot.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, as
 * {@code ItemSearchDatabaseTest} describes, and CI runs it the same way. It migrates a schema of its
 * own with a random name and drops only that schema.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("the search demand log, against a real database")
class SearchDemandDatabaseTest {

    /** Hamra, Beirut: where the customer is standing. */
    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);

    /** Achrafieh, about 2.5 km east: another neighbourhood entirely. */
    private static final GeoPoint ACHRAFIEH = GeoPoint.of(33.886000d, 35.516000d);

    /** Jounieh, sixteen kilometres up the coast: outside every area's cap. */
    private static final GeoPoint JOUNIEH = GeoPoint.of(33.980800d, 35.617800d);

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");

    /** A Wednesday, so "the week" is a Monday the test can name. */
    private static final Instant NOW =
            Instant.parse("2026-09-16T10:30:00Z").truncatedTo(ChronoUnit.SECONDS);

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "search_demand_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private TransactionTemplate tx;
    private SearchDemandLogRepository logs;
    private SearchDemandSeenRepository seen;
    private SearchDemandWeekRepository weeks;
    private SearchDemandDigestRepository digests;
    private DeliveryZoneRepository zones;
    private StoreRepository stores;
    private ProductRepository products;
    private UnmetDemand unmet;
    private CoarseAreas areas;
    private final DemandWeeks calendar = new DemandWeeks(BEIRUT);

    /** A secret as the environment hands one over. Nothing like it is ever in the repository. */
    private final SeenKeys keys = new SeenKeys("database-test-secret-not-a-real-one");

    private UUID hamra;
    private UUID achrafieh;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

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
        // A shared entity manager, so every repository call joins whatever transaction the template
        // opened — which is how the service runs, and what lets the recorder's own transaction be
        // the real thing rather than a stand-in.
        EntityManager shared = SharedEntityManagerCreator.createSharedEntityManager(entityManagerFactory);
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(shared);
        logs = repositories.getRepository(SearchDemandLogRepository.class);
        seen = repositories.getRepository(SearchDemandSeenRepository.class);
        weeks = repositories.getRepository(SearchDemandWeekRepository.class);
        digests = repositories.getRepository(SearchDemandDigestRepository.class);
        zones = repositories.getRepository(DeliveryZoneRepository.class);
        stores = repositories.getRepository(StoreRepository.class);
        products = repositories.getRepository(ProductRepository.class);
        tx = new TransactionTemplate(transactionManager());

        tx.executeWithoutResult(status -> {
            hamra = placed("Hamra", "Beirut", 1, 33.897500d, 35.482000d);
            achrafieh = placed("Achrafieh", "Beirut", 2, 33.886500d, 35.516500d);
        });

        areas = new CoarseAreas(zones, Clock.fixed(NOW, ZoneOffset.UTC), 3_000);
        unmet = new UnmetDemand(logs, seen, weeks, digests, keys, calendar,
                Clock.fixed(NOW, ZoneOffset.UTC), 2_000, 10, 90);
    }

    @BeforeEach
    void emptyTheTables() {
        tx.executeWithoutResult(status -> {
            logs.deleteAllInBatch();
            seen.deleteAllInBatch();
            weeks.deleteAllInBatch();
            digests.deleteAllInBatch();
        });
        areas.forget();
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

    /**
     * The privacy promise, as a fact about the schema. If somebody adds {@code account_id},
     * {@code session_id}, {@code latitude} or anything else that could follow a person, this fails —
     * which is the point. Changing the list is then a deliberate act with a reviewer attached.
     */
    @Test
    @DisplayName("the log has exactly these columns, and none that could follow a person")
    void the_log_holds_nothing_personal() throws SQLException {
        assertThat(columnsOf("search_demand_log")).containsExactlyInAnyOrder(
                "id", "searched_at", "area_id", "term", "result_count", "in_own_area",
                "nearest_metres", "vertical");

        // Spelled out again as the absences they are, so the reason survives a rename.
        assertThat(columnsOf("search_demand_log"))
                .doesNotContain("account_id", "customer_id", "user_id", "session_id", "device_id",
                        "ip", "ip_address", "user_agent", "latitude", "longitude", "location",
                        "pin", "lat", "lng");

        // And the key is random rather than sequential, so the order rows were written in is not
        // readable either.
        assertThat(scalar("SELECT data_type FROM information_schema.columns WHERE table_schema = '"
                + schema + "' AND table_name = 'search_demand_log' AND column_name = 'id'"))
                .isEqualTo("uuid");
    }

    /**
     * The claim the first version of this migration made in a comment, tested instead of asserted in
     * prose: a random primary key does not hide the order rows were written in. {@code ORDER BY ctid}
     * reads an insert-only table in physical order, which is insertion order — so the recorder
     * shuffles every flush, and this is the proof that it does.
     *
     * <p>Written through the recorder rather than through the repository, because the shuffle is the
     * writer's job and this has to fail if somebody takes it out.
     */
    @Test
    @DisplayName("the heap does not give the order the searches happened in back")
    void the_physical_order_is_not_the_search_order() throws SQLException {
        SearchDemandRecorder recorder = recorder(Duration.ZERO, 40);
        List<String> asSearched = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            String term = "term-" + (i < 10 ? "0" + i : i);
            asSearched.add(term);
            recorder.record(new Recording("account-" + i, term, HAMRA, 0, null, List.of(), null));
        }

        List<String> asStored = terms("SELECT term FROM search_demand_log ORDER BY ctid");

        assertThat(asStored).containsExactlyInAnyOrderElementsOf(asSearched);
        // Every row is there; the sequence that would read as one street's afternoon is not.
        assertThat(asStored).isNotEqualTo(asSearched);
        // And the id gives nothing either: random uuids sort into an order of their own.
        assertThat(terms("SELECT term FROM search_demand_log ORDER BY id")).isNotEqualTo(asSearched);
    }

    // ------------------------------------------------------------------------------ one row, coarse

    @Test
    @DisplayName("a search writes exactly one row: the folded term, the area, and no pin")
    void a_search_writes_one_coarse_row() {
        SearchDemandRecorder recorder = recorder(Duration.ZERO);
        recorder.record(new Recording("account-1", "حفاضات", HAMRA, 0, null, List.of(), null));

        assertThat(recorder.counts().failed()).isZero();
        assertThat(logs.count()).isEqualTo(1);
        SearchDemandLog row = logs.findAll().get(0);
        assertThat(row.getTerm()).isEqualTo("حفاضات");
        assertThat(row.getAreaId()).isEqualTo(hamra);
        assertThat(row.getResultCount()).isZero();
        assertThat(row.isInOwnArea()).isFalse();
        assertThat(row.getNearestMetres()).isNull();
        // The hour, not the minute: 10:30 was recorded as 10:00.
        assertThat(row.getSearchedAt()).isEqualTo(Instant.parse("2026-09-16T10:00:00Z"));
    }

    @Test
    @DisplayName("a pin too far from every area belongs to none, rather than to the nearest")
    void a_distant_pin_belongs_to_no_area() {
        recorder(Duration.ZERO)
                .record(new Recording("account-1", "rice", JOUNIEH, 0, null, List.of(), null));

        assertThat(logs.findAll()).singleElement()
                .satisfies(row -> assertThat(row.getAreaId()).isNull());
    }

    @Test
    @DisplayName("an answering shop in the searcher's own area is said so; one two areas away is not")
    void in_own_area_compares_two_neighbourhoods() {
        SearchDemandRecorder recorder = recorder(Duration.ZERO);

        recorder.record(new Recording("a", "milk", HAMRA, 1, 300d,
                List.of(GeoPoint.of(33.897000d, 35.483000d)), null));
        recorder.record(new Recording("b", "cheese", HAMRA, 1, 2_600d, List.of(ACHRAFIEH), null));

        Map<String, SearchDemandLog> byTerm = new HashMap<>();
        logs.findAll().forEach(row -> byTerm.put(row.getTerm(), row));
        assertThat(byTerm.get("milk").isInOwnArea()).isTrue();
        assertThat(byTerm.get("cheese").isInOwnArea()).isFalse();
        // Banded up to the next 250 m, never the metre the customer could be placed by.
        assertThat(byTerm.get("milk").getNearestMetres()).isEqualTo(500);
        assertThat(byTerm.get("cheese").getNearestMetres()).isEqualTo(2_750);
    }

    @Test
    @DisplayName("one account asking twice inside the window is one search, and the account is not stored")
    void repeats_from_one_session_collapse() {
        SearchDemandRecorder recorder = recorder(Duration.ofMinutes(30));

        for (int i = 0; i < 9; i++) {
            recorder.record(new Recording("account-1", "حفاضات", HAMRA, 0, null, List.of(), null));
        }
        recorder.record(new Recording("account-2", "حفاضات", HAMRA, 0, null, List.of(), null));

        assertThat(logs.count()).isEqualTo(2);
        assertThat(recorder.counts().repeats()).isEqualTo(8);
    }

    /** The insert cannot describe an answer that never came: the constraint says so. */
    @Test
    @DisplayName("a row with no results cannot claim a distance or an area hit")
    void an_empty_answer_cannot_claim_a_distance() {
        assertThatThrownBy(() -> execute("INSERT INTO search_demand_log "
                + "(id, searched_at, area_id, term, result_count, in_own_area, nearest_metres) "
                + "VALUES (gen_random_uuid(), now(), '" + hamra + "', 'rice', 0, true, 900)"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_search_demand_log_empty");

        // The writer already refuses it, so the constraint is a second line rather than the only one.
        SearchDemandLog honest = new SearchDemandLog(NOW, hamra, "rice", 0, true, 900d, null);
        assertThat(honest.isInOwnArea()).isFalse();
        assertThat(honest.getNearestMetres()).isNull();
    }

    // ------------------------------------------------------------------------------- the weekly job

    @Test
    @DisplayName("the week ignores terms under five distinct searches, and counts rows not repeats")
    void the_week_applies_the_floor() {
        Instant week = calendar.weekOf(NOW);
        searches(hamra, "حفاضات", 9, 0, null);
        searches(hamra, "زعتر", 4, 0, null);
        searches(achrafieh, "حفاضات", 5, 0, null);

        tx.executeWithoutResult(status -> unmet.rollUp(week));

        List<SearchDemandWeek> rows = weeks.findAll();
        assertThat(rows).extracting(SearchDemandWeek::getTerm).containsOnly("حفاضات");
        assertThat(rows).hasSize(2);
        assertThat(rows).allMatch(row -> row.getKind() == SearchDemandWeek.Kind.NONE);
        assertThat(rows).filteredOn(row -> row.getAreaId().equals(hamra))
                .singleElement()
                .satisfies(row -> {
                    assertThat(row.getSearches()).isEqualTo(9);
                    assertThat(row.getRank()).isEqualTo(1);
                });
        // Said as a band, never as nine.
        assertThat(UnmetDemand.band(9)).isEqualTo(5);
        assertThat(UnmetDemand.band(14)).isEqualTo(10);
    }

    @Test
    @DisplayName("a term answered only by shops past two kilometres is FAR, one answered nearby is neither")
    void far_and_near_answers() {
        Instant week = calendar.weekOf(NOW);
        searches(hamra, "جبنة", 6, 1, 2_750);
        searches(hamra, "خبز", 6, 1, 500);

        tx.executeWithoutResult(status -> unmet.rollUp(week));

        assertThat(weeks.findAll()).singleElement().satisfies(row -> {
            assertThat(row.getTerm()).isEqualTo("جبنة");
            assertThat(row.getKind()).isEqualTo(SearchDemandWeek.Kind.FAR);
        });
    }

    @Test
    @DisplayName("searches in another week are another week's, cut at Monday midnight in Beirut")
    void weeks_are_cut_in_the_platforms_zone() {
        Instant week = calendar.weekOf(NOW);
        Instant before = calendar.weekBefore(week);

        // 21:30 UTC on the Sunday is 00:30 Monday in Beirut: the new week, not the old one.
        Instant sundayNight = Instant.parse("2026-09-13T21:30:00Z");
        assertThat(calendar.weekOf(sundayNight)).isEqualTo(week);
        assertThat(calendar.weekOf(sundayNight.minus(Duration.ofHours(2)))).isEqualTo(before);

        searches(hamra, "رز", 5, 0, null, sundayNight);
        searches(hamra, "رز", 5, 0, null, sundayNight.minus(Duration.ofHours(2)));

        tx.executeWithoutResult(status -> unmet.rollUp(week));
        assertThat(weeks.findAll()).singleElement()
                .satisfies(row -> assertThat(row.getSearches()).isEqualTo(5));
    }

    @Test
    @DisplayName("rolling a week up twice leaves one set of rows")
    void the_roll_up_is_idempotent() {
        Instant week = calendar.weekOf(NOW);
        searches(hamra, "حفاضات", 7, 0, null);

        tx.executeWithoutResult(status -> unmet.rollUp(week));
        tx.executeWithoutResult(status -> unmet.rollUp(week));

        assertThat(weeks.count()).isEqualTo(1);
    }

    // ----------------------------------------------------------------- the floor counts people

    /**
     * The hole the review found, as a test. The in-memory repeat window collapses a burst, not a
     * week, so one household looking for the same thing on five evenings was five rows — and a floor
     * of five rows is a floor one household clears alone. Five searches, five days, one account:
     * nothing is published.
     */
    @Test
    @DisplayName("one account searching five times across five days publishes nothing")
    void one_household_cannot_clear_the_floor_alone() {
        Instant week = calendar.weekOf(NOW);
        Instant monday = Instant.parse("2026-09-14T09:00:00Z");
        for (int day = 0; day < 5; day++) {
            Instant when = monday.plus(Duration.ofDays(day));
            // A different day each time, so the recorder's repeat window collapses none of them.
            recorder(Duration.ofMinutes(30), 1, when, keys)
                    .record(new Recording("one-account", "insulin glargine", HAMRA, 0, null,
                            List.of(), null));
        }

        // Five searches really were recorded: it is the floor that refuses them, not the log.
        assertThat(logs.count()).isEqualTo(5);
        assertThat(seen.count()).isEqualTo(1);

        tx.executeWithoutResult(status -> unmet.rollUp(week));
        assertThat(weeks.findAll()).isEmpty();
    }

    /** And the other half: five different people asking once each is a market signal. */
    @Test
    @DisplayName("five accounts asking once each publishes the term")
    void five_people_clear_the_floor() {
        Instant week = calendar.weekOf(NOW);
        Instant monday = Instant.parse("2026-09-14T09:00:00Z");
        for (int person = 0; person < 5; person++) {
            recorder(Duration.ofMinutes(30), 1, monday, keys)
                    .record(new Recording("account-" + person, "insulin glargine", HAMRA, 0, null,
                            List.of(), null));
        }

        assertThat(seen.count()).isEqualTo(5);

        tx.executeWithoutResult(status -> unmet.rollUp(week));
        assertThat(weeks.findAll()).singleElement().satisfies(row -> {
            assertThat(row.getTerm()).isEqualTo("insulin glargine");
            assertThat(row.getSearches()).isEqualTo(5);
        });
    }

    /**
     * A merchant's four searches of their own no longer buy them a neighbour's fifth: four people is
     * four people whoever they are, and the fifth term stays unpublished.
     */
    @Test
    @DisplayName("four searches of a merchant's own do not publish a neighbour's search")
    void a_merchant_cannot_buy_a_neighbours_term() {
        Instant week = calendar.weekOf(NOW);
        Instant monday = Instant.parse("2026-09-14T09:00:00Z");
        for (int i = 0; i < 4; i++) {
            recorder(Duration.ZERO, 1, monday.plus(Duration.ofHours(i)), keys)
                    .record(new Recording("the-merchant", "methadone", HAMRA, 0, null, List.of(),
                            null));
        }
        recorder(Duration.ZERO, 1, monday.plus(Duration.ofHours(5)), keys)
                .record(new Recording("the-neighbour", "methadone", HAMRA, 0, null, List.of(), null));

        assertThat(logs.count()).isEqualTo(5);
        assertThat(seen.count()).isEqualTo(2);

        tx.executeWithoutResult(status -> unmet.rollUp(week));
        assertThat(weeks.findAll()).isEmpty();
    }

    /**
     * What the marker is, and what it is not. It is not the account, it is not the same value for
     * the same person's next term, and it is the same value when that person asks again — which is
     * the only property the count needs.
     */
    @Test
    @DisplayName("a seen marker is not an account, and does not follow a person from term to term")
    void the_marker_says_nothing_about_who() throws SQLException {
        assertThat(columnsOf("search_demand_seen")).containsExactlyInAnyOrder(
                "seen_key", "key_id", "week_start", "area_id", "term", "created_at");
        assertThat(columnsOf("search_demand_seen"))
                .doesNotContain("account_id", "customer_id", "user_id", "session_id", "device_id");

        Instant week = calendar.weekOf(NOW);
        String nappies = keys.keyFor("account-1", hamra, "حفاضات", week).orElseThrow();
        String rice = keys.keyFor("account-1", hamra, "رز", week).orElseThrow();
        String elsewhere = keys.keyFor("account-1", achrafieh, "حفاضات", week).orElseThrow();
        String lastWeek = keys.keyFor("account-1", hamra, "حفاضات", calendar.weekBefore(week))
                .orElseThrow();
        String somebodyElse = keys.keyFor("account-2", hamra, "حفاضات", week).orElseThrow();

        // The same question asked twice is the same marker: that is what makes five rows five people.
        assertThat(keys.keyFor("account-1", hamra, "حفاضات", week)).contains(nappies);
        // Everything else about it differs, so nothing here can be joined into "this person's week".
        assertThat(List.of(rice, elsewhere, lastWeek, somebodyElse)).doesNotContain(nappies);
        assertThat(nappies).doesNotContain("account-1").hasSize(64);
    }

    /** With no secret there is nothing to count people by, so nothing is computed at all. */
    @Test
    @DisplayName("with no secret, a week is not rolled up rather than rolled up on a weak floor")
    void no_secret_means_no_roll_up() {
        Instant week = calendar.weekOf(NOW);
        searches(hamra, "حفاضات", 9, 0, null);
        UnmetDemand unkeyed = new UnmetDemand(logs, seen, weeks, digests, new SeenKeys(""), calendar,
                Clock.fixed(NOW, ZoneOffset.UTC), 2_000, 10, 90);

        int rolledWithoutASecret = tx.execute(status -> unkeyed.rollUp(week));
        assertThat(rolledWithoutASecret).isZero();
        assertThat(weeks.findAll()).isEmpty();

        // The same week, with the secret in place, is published — so it was the secret that decided.
        tx.executeWithoutResult(status -> unmet.rollUp(week));
        assertThat(weeks.findAll()).hasSize(1);
    }

    /** A rotated secret starts the count again rather than counting the same person twice. */
    @Test
    @DisplayName("a rotated secret reads as nobody having asked yet")
    void a_rotated_secret_does_not_double_count() {
        Instant week = calendar.weekOf(NOW);
        searches(hamra, "حفاضات", 9, 0, null);
        SeenKeys rotated = new SeenKeys("database-test-secret-AFTER-the-rotation");
        UnmetDemand afterRotation = new UnmetDemand(logs, seen, weeks, digests, rotated, calendar,
                Clock.fixed(NOW, ZoneOffset.UTC), 2_000, 10, 90);

        assertThat(rotated.keyId()).isNotEqualTo(keys.keyId());
        int rolledAfterRotation = tx.execute(status -> afterRotation.rollUp(week));
        assertThat(rolledAfterRotation).isZero();
        assertThat(weeks.findAll()).isEmpty();
    }

    // --------------------------------------------------------------------------------- retention

    @Test
    @DisplayName("retention forgets searches older than ninety days and nothing newer")
    void retention_deletes_only_the_old() {
        Instant old = NOW.minus(Duration.ofDays(91));
        Instant justInside = NOW.minus(Duration.ofDays(89));
        searches(hamra, "قديم", 3, 0, null, old);
        searches(hamra, "جديد", 3, 0, null, justInside);

        tx.executeWithoutResult(status -> unmet.forgetOldSearches());

        assertThat(logs.findAll()).extracting(SearchDemandLog::getTerm).containsOnly("جديد");
    }

    /**
     * The seen markers are the only rows in this feature with a per-person value in them, even an
     * unreadable one, so they go first: they bound one week's floor, and the roll-up never looks
     * further back than last week.
     */
    @Test
    @DisplayName("seen markers are kept for this week and last, and no longer")
    void seen_markers_do_not_outlive_the_week_they_bound() {
        Instant thisWeek = calendar.weekOf(NOW);
        Instant lastWeek = calendar.weekBefore(thisWeek);
        Instant theWeekBefore = calendar.weekBefore(lastWeek);
        searches(hamra, "هذا-الأسبوع", 3, 0, null, NOW);
        searches(hamra, "الأسبوع-الماضي", 3, 0, null, lastWeek.plus(Duration.ofDays(1)));
        searches(hamra, "قبل-ذلك", 3, 0, null, theWeekBefore.plus(Duration.ofDays(1)));
        assertThat(seen.count()).isEqualTo(9);

        tx.executeWithoutResult(status -> unmet.forgetOldSearches());

        // The searches themselves are all inside ninety days and stay; only the markers expire.
        assertThat(logs.count()).isEqualTo(9);
        assertThat(seen.count()).isEqualTo(6);
        assertThat(seen.findAll()).extracting(SearchDemandSeen::getWeekStart)
                .containsOnly(thisWeek, lastWeek);
    }

    // ------------------------------------------------------------------- what the merchant sells

    /**
     * The one query a mock cannot stand in for: it matches a week's terms against
     * {@code products.search_name}, the generated column V37 folds every product name into. Java has
     * no copy of that fold, so "does this merchant already sell nescafe" can only be asked here.
     */
    @Test
    @DisplayName("a term the merchant already sells is recognised through the search's own fold")
    void already_sold_is_matched_on_the_folded_name() {
        Instant week = calendar.weekOf(NOW);
        UUID shop = aShopSelling("Nescafé Classic 200g", "حليب نيدو كامل الدسم");
        SearchDemandWeek sold = row(week, "nescafe");
        SearchDemandWeek alsoSold = row(week, "نيدو");
        SearchDemandWeek wanted = row(week, "حفاضات");
        tx.executeWithoutResult(status -> weeks.saveAll(List.of(sold, alsoSold, wanted)));

        List<UUID> matched = weeks.alreadySold(
                List.of(sold.getId(), alsoSold.getId(), wanted.getId()), List.of(shop));

        assertThat(matched).containsExactlyInAnyOrder(sold.getId(), alsoSold.getId());
        // Another merchant's shelf is not this merchant's answer.
        assertThat(weeks.alreadySold(List.of(sold.getId()), List.of(UUID.randomUUID()))).isEmpty();
    }

    // ----------------------------------------------------------------------------- the digest ledger

    @Test
    @DisplayName("a merchant's week can only be claimed once, whoever tries")
    void the_digest_ledger_refuses_a_second_claim() {
        Instant week = calendar.weekOf(NOW);
        tx.executeWithoutResult(status ->
                digests.saveAndFlush(new SearchDemandDigest(week, "merchant-1", 3, NOW)));

        // The unique key, named: DemandDigestClaim reads exactly this refusal as "already taken",
        // and DemandDigestTest checks that it does.
        assertThatThrownBy(() -> tx.executeWithoutResult(status ->
                digests.saveAndFlush(new SearchDemandDigest(week, "merchant-1", 2, NOW))))
                .hasMessageContaining("uq_search_demand_digest");

        assertThat(digests.existsByWeekStartAndMerchantId(week, "merchant-1")).isTrue();
        assertThat(digests.existsByWeekStartAndMerchantId(week, "merchant-2")).isFalse();
        // Another week is another claim.
        tx.executeWithoutResult(status -> digests.saveAndFlush(
                new SearchDemandDigest(calendar.weekBefore(week), "merchant-1", 1, NOW)));
        assertThat(digests.count()).isEqualTo(2);
    }

    // ------------------------------------------------------------------------------------ helpers

    private SearchDemandRecorder recorder(Duration repeatWindow) {
        // One row per flush, so the assertion that follows sees the row. What the buffer is really
        // for is proved on its own, below, where a flush is big enough to be shuffled.
        return recorder(repeatWindow, 1);
    }

    private SearchDemandRecorder recorder(Duration repeatWindow, int flushRows) {
        return recorder(repeatWindow, flushRows, NOW, keys);
    }

    /**
     * Inline, so the assertion that follows sees the row. The pool is the production path and is
     * covered where it matters: that record() returns before the write happens.
     */
    private SearchDemandRecorder recorder(Duration repeatWindow, int flushRows, Instant now,
                                          SeenKeys secret) {
        return new SearchDemandRecorder(logs, seen, secret, calendar, areas,
                Clock.fixed(now, ZoneOffset.UTC), transactionManager(), Runnable::run, repeatWindow,
                flushRows, Duration.ofMinutes(10));
    }

    private void searches(UUID area, String term, int howMany, int results, Integer nearest) {
        searches(area, term, howMany, results, nearest, NOW);
    }

    /**
     * One search each from {@code howMany} different people: the rows a week's count is made of, and
     * the markers its floor is counted from.
     *
     * <p>Written straight rather than through the recorder, so a test can say exactly how many
     * people and how many searches there were — which is the distinction the floor turns on.
     */
    private void searches(UUID area, String term, int howMany, int results, Integer nearest,
                          Instant at) {
        tx.executeWithoutResult(status -> {
            List<SearchDemandLog> rows = new ArrayList<>();
            for (int i = 0; i < howMany; i++) {
                rows.add(new SearchDemandLog(at, area, term, results, false,
                        nearest == null ? null : nearest.doubleValue(), null));
            }
            logs.saveAll(rows);
            for (int i = 0; i < howMany; i++) {
                asked("person-" + i, area, term, at);
            }
        });
    }

    /** "This person asked for this term, in this area, in this week" — the row the floor counts. */
    private void asked(String accountId, UUID area, String term, Instant at) {
        Instant week = calendar.weekOf(SearchDemandLog.at(at));
        keys.keyFor(accountId, area, term, week)
                .ifPresent(key -> seen.remember(key, keys.keyId(), week, area, term, at));
    }

    private SearchDemandWeek row(Instant week, String term) {
        return new SearchDemandWeek(week, hamra, term, SearchDemandWeek.Kind.NONE, 9, 1, NOW);
    }

    /** A live shop with these products on its shelf, and its id. */
    private UUID aShopSelling(String... names) {
        return tx.execute(status -> {
            Store shop = new Store("merchant-" + UUID.randomUUID(), "Corner Grocer",
                    Store.Vertical.GROCERY);
            shop.pinAt(GeoPoint.of(33.8977d, 35.4829d));
            shop.replaceHours(java.util.Arrays.stream(java.time.DayOfWeek.values())
                    .map(day -> new StoreHours(day, java.time.LocalTime.MIDNIGHT,
                            java.time.LocalTime.of(23, 59, 59)))
                    .toList());
            shop.publish(NOW.minus(Duration.ofDays(30)));
            stores.save(shop);
            for (String name : names) {
                Product product = new Product(shop.getMerchantId(), shop.getId(), name, null,
                        new java.math.BigDecimal("1.50"), null);
                product.addImage("products/" + UUID.randomUUID() + ".jpg");
                product.publish();
                products.save(product);
            }
            return shop.getId();
        });
    }

    private UUID placed(String name, String region, int order, double lat, double lng) {
        DeliveryZone zone = new DeliveryZone(name, region, order);
        zone.placeAt(GeoPoint.of(lat, lng));
        return zones.save(zone).getId();
    }

    private PlatformTransactionManager transactionManager() {
        return new JpaTransactionManager(entityManagerFactory);
    }

    private List<String> columnsOf(String table) throws SQLException {
        List<String> names = new ArrayList<>();
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(
                     "SELECT column_name FROM information_schema.columns WHERE table_schema = '"
                             + schema + "' AND table_name = '" + table + "'")) {
            while (rows.next()) {
                names.add(rows.getString(1));
            }
        }
        return names;
    }

    private void execute(String sql) throws SQLException {
        try (Connection connection = connection(); Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    /** One text column, in the order the query asked for. */
    private List<String> terms(String sql) throws SQLException {
        List<String> values = new ArrayList<>();
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            while (rows.next()) {
                values.add(rows.getString(1));
            }
        }
        return values;
    }

    private String scalar(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getString(1);
        }
    }

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(urlInSchema(), user, password);
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
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it. That is what makes this test an assertion about V40.
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
