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
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.product.domain.ItemSearchRepository.Candidate;
import com.delivery.product.service.ItemSearchService;
import com.delivery.product.service.ItemSearchService.ItemQuery;
import com.delivery.product.service.ItemSearchService.ItemSearchResult;
import com.delivery.product.service.ItemSearchService.SearchRefusedException;
import com.delivery.product.service.ItemSearchService.SearchTimedOutException;
import com.delivery.product.service.SearchPatterns;
import com.delivery.product.service.SearchWords;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * V37 and the item search's SQL, against a real PostgreSQL with PostGIS and pg_trgm.
 *
 * <p>The customer item search matches words in SQL: the fold ({@code search_fold}), the tiers, the
 * trigram index, the filters that keep services, drafts, closed and far shops out, and the caps that
 * decide which rows a large answer keeps ({@link ItemSearchRepository#findCandidateRows}). Nothing
 * short of a database can check any of that, and the service's own tests stand a Java copy in for it.
 * So this migrates a schema from empty to the latest version, validates every entity against it as the
 * service does at boot, and asks the real queries.
 *
 * <p>Arabic in particular can only be checked here. pg_trgm splits text into words using what the
 * database's locale calls a letter or digit: on the platform's image ({@code postgis/postgis:17-3.5},
 * {@code en_US.utf8}) Arabic letters are letters, and the fuzzy tier matches Arabic; in a database
 * created with the C locale they would not be, and only the substring tiers would. The first test below
 * says which this database is.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, as
 * {@code ServicesVerticalDatabaseTest} describes, and CI runs it the same way. It migrates a schema of
 * its own with a random name and drops only that schema.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("the item search, against a real database")
class ItemSearchDatabaseTest {

    /** Hamra, Beirut: where the customer is standing. */
    private static final GeoPoint HAMRA = GeoPoint.of(33.897700d, 35.482900d);

    private static final Instant NOW = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");

    private static final String EAN = "5449000000996";

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "item_search_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private JpaRepositoryFactory repositories;
    private ItemSearchRepository search;
    private ProductRepository products;
    private StoreRepository stores;

    /** Every product this test made, by id, so the demo storefront's rows never enter an assertion. */
    private final Map<UUID, String> mine = new LinkedHashMap<>();

    private Store hamraGrocer;
    private Store downtownMarket;
    private Store jouniehGrocer;
    private Store press;
    private Store suspendedGrocer;
    private Store smallCircle;
    private Product renameMe;

    /** Six shops that sell four equal "Zinger Cola"s each, a block apart going north from Hamra. */
    private final List<Store> zingerShops = new ArrayList<>();
    /** Nearer than all of them, and closed today. */
    private Store zingerClosed;

    private Store openInBeirut;
    private Store offsetZone;
    private Store unknownZone;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

    @BeforeAll
    void migrateFromEmptyThenSeed() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // What infra/postgres/init provides on every environment.
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
            statement.execute("CREATE SCHEMA " + schema);
        }
        Flyway.configure()
                .dataSource(url, user, password)
                .schemas(schema)
                .defaultSchema(schema)
                // The locations and the ordering rule application.yml gives the service.
                .locations("classpath:db/migration/shared", "classpath:db/migration/product")
                .outOfOrder(true)
                .load()
                .migrate();

        entityManagerFactory = entityManagerFactory();
        em = entityManagerFactory.createEntityManager();
        repositories = new JpaRepositoryFactory(em);
        search = repositories.getRepository(ItemSearchRepository.class);
        products = repositories.getRepository(ProductRepository.class);
        stores = repositories.getRepository(StoreRepository.class);

        em.getTransaction().begin();
        hamraGrocer = listed(new Store("merchant-hamra", "Hamra Grocer", Store.Vertical.GROCERY),
                33.898600d, 35.483400d);
        downtownMarket = listed(new Store("merchant-downtown", "Downtown Market", Store.Vertical.GROCERY),
                33.895800d, 35.500900d);
        // Some 17 km up the coast.
        jouniehGrocer = listed(new Store("merchant-jounieh", "Jounieh Grocer", Store.Vertical.GROCERY),
                33.980800d, 35.617800d);
        press = listed(new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                Store.ServiceCategory.PRINTING), 33.898200d, 35.482500d);
        suspendedGrocer = listed(new Store("merchant-shut", "Suspended Grocer", Store.Vertical.GROCERY),
                33.899000d, 35.483000d);
        suspendedGrocer.suspend();
        // ~1.7 km from the customer, and it carries one kilometre.
        smallCircle = listed(new Store("merchant-circle", "Small Circle Grocer", Store.Vertical.GROCERY),
                33.895800d, 35.501000d);
        smallCircle.setDeliveryRadiusMetres(1_000);
        for (Store store : List.of(hamraGrocer, downtownMarket, jouniehGrocer, press, suspendedGrocer,
                smallCircle)) {
            em.persist(store);
        }

        live(hamraGrocer, "Pepsi 1L").assignCodes(null, EAN);
        live(hamraGrocer, "Diet Pepsi Can");
        live(hamraGrocer, "شاي أحمد");
        live(hamraGrocer, "حليب نيدو كامل الدسم");
        live(hamraGrocer, "Nescafé Classic 200g");
        live(hamraGrocer, "Lay's Salted");
        live(hamraGrocer, "حلوى");
        live(hamraGrocer, "شوكولاتة كيت كات");
        live(hamraGrocer, "قَهْوَة نجار");
        live(hamraGrocer, "بيبسي ٣ لتر");
        live(hamraGrocer, "Coca-Cola Bottle");
        live(hamraGrocer, "ڤيمتو");
        live(hamraGrocer, "Mild Cheddar");
        live(hamraGrocer, "Ricotta Cheese");
        live(hamraGrocer, "Tunisian Harissa");
        live(hamraGrocer, "Milk Chocolate Bar");
        live(hamraGrocer, "رز بسمتي");
        live(hamraGrocer, "رزمة مناديل");
        live(hamraGrocer, "Pepsi Max").applyStockProjection(false);
        Product draft = new Product(hamraGrocer.getMerchantId(), hamraGrocer.getId(), "Pepsi Twist",
                null, new BigDecimal("1.00"), null);
        em.persist(draft);
        mine.put(draft.getId(), draft.getName());
        renameMe = live(hamraGrocer, "Rename Me");
        live(downtownMarket, "Pepsi 330ml").assignCodes(null, EAN);
        live(jouniehGrocer, "Pepsi 1L");
        live(press, "Pepsi flyers");
        live(suspendedGrocer, "Pepsi 1L");
        live(smallCircle, "Pepsi 1L");

        // A block (~111 m) apart going north from Hamra, and the closed one nearest of all.
        for (int i = 0; i < 6; i++) {
            Store shop = listed(new Store("merchant-zinger-" + i, "Zinger Shop " + i, Store.Vertical.GROCERY),
                    33.899000d + i * 0.001d, 35.482900d);
            em.persist(shop);
            zingerShops.add(shop);
            for (int j = 0; j < 4; j++) {
                live(shop, "Zinger Cola " + j);
            }
        }
        zingerShops.get(5).applyRating(new BigDecimal("4.9"), 40);
        zingerShops.get(4).applyRating(new BigDecimal("4.5"), 12);
        zingerClosed = listed(new Store("merchant-zinger-shut", "Zinger Closed Today", Store.Vertical.GROCERY),
                33.898000d, 35.482900d);
        zingerClosed.replaceHours(List.of(new StoreHours(
                NOW.atZone(ZoneOffset.UTC).getDayOfWeek().plus(3), LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59))));
        em.persist(zingerClosed);
        live(zingerClosed, "Zinger Cola Shut");

        // Open for the hour around now at the shop, in Beirut: closed at that hour read in UTC.
        ZonedDateTime beirutNow = NOW.atZone(BEIRUT);
        LocalTime local = beirutNow.toLocalTime();
        openInBeirut = listed(new Store("merchant-beirut", "Open In Beirut", Store.Vertical.GROCERY),
                33.897000d, 35.484000d);
        openInBeirut.updateProfile(openInBeirut.getName(), null, null, Store.Vertical.GROCERY, null,
                "Asia/Beirut", null);
        openInBeirut.replaceHours(List.of(new StoreHours(beirutNow.getDayOfWeek(),
                local.isBefore(LocalTime.of(0, 30)) ? LocalTime.MIDNIGHT : local.minusMinutes(30),
                local.isAfter(LocalTime.of(23, 29)) ? LocalTime.of(23, 59, 59) : local.plusMinutes(30))));
        // Closed today whichever way their zone is read, but a zone only the service can read.
        offsetZone = listed(new Store("merchant-offset", "Offset Zone", Store.Vertical.GROCERY),
                33.897000d, 35.485000d);
        offsetZone.updateProfile(offsetZone.getName(), null, null, Store.Vertical.GROCERY, null, "+03:00",
                null);
        unknownZone = listed(new Store("merchant-mars", "Unknown Zone", Store.Vertical.GROCERY),
                33.897000d, 35.486000d);
        unknownZone.updateProfile(unknownZone.getName(), null, null, Store.Vertical.GROCERY, null,
                "Mars/Olympus", null);
        for (Store shop : List.of(offsetZone, unknownZone)) {
            shop.replaceHours(List.of(new StoreHours(NOW.atZone(ZoneOffset.UTC).getDayOfWeek().plus(3),
                    LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59))));
        }
        for (Store shop : List.of(openInBeirut, offsetZone, unknownZone)) {
            em.persist(shop);
        }
        live(openInBeirut, "Quokka Juice");
        live(offsetZone, "Quokka Nectar");
        live(unknownZone, "Quokka Syrup");

        Store filler = listed(new Store("merchant-filler", "Filler Grocer", Store.Vertical.GROCERY),
                33.890000d, 35.480000d);
        em.persist(filler);
        em.getTransaction().commit();
        em.clear();

        // A catalogue the size of a real one, so the planner weighs the indexes as it would on dev: with
        // a few dozen rows every plan costs nothing. Inserted after the index was built and never
        // vacuumed, which is how a merchant's new products reach it: V37 builds the index without a
        // pending list, so they are in it at once, and the plan below holds it to that.
        execute("INSERT INTO products (id, merchant_id, store_id, name, price, image_refs, status) "
                + "SELECT gen_random_uuid(), 'merchant-filler', '" + filler.getId() + "', "
                + "'Filler item ' || g, 1.00, '[]'::jsonb, 'ACTIVE' FROM generate_series(1, 5000) g");
        execute("ANALYZE products");
        execute("ANALYZE stores");
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

    // ------------------------------------------------------------------------------------ the fold

    @Test
    @DisplayName("this database's locale reads Arabic letters as letters, as the platform's does")
    void arabic_letters_are_letters_to_pg_trgm() throws SQLException {
        assertThat(scalar("SELECT cardinality(public.show_trgm('حليب'))")).isEqualTo("5");
    }

    @Test
    @DisplayName("the fold spells each pair the same way")
    void fold_pairs_fold_alike() throws SQLException {
        String[][] pairs = {
                {"أحمد", "احمد"},
                {"إبريق", "ابريق"},
                {"آخر", "اخر"},
                {"مكتبة", "مكتبه"},
                {"مصطفى", "مصطفي"},
                {"مُحَمَّد", "محمد"},
                {"كـــتاب", "كتاب"},
                {"٣", "3"},
                {"۳", "3"},
                {"Nescafé", "nescafe"},
                {"NESCAFÉ", "nescafe"},
                {"Lay's", "lays"},
                {"Lay’s", "lays"},
                {"PEPSI  1L", "pepsi 1l"},
                // The Persian letters Lebanese shops write foreign names with, and what a reader types.
                {"ڤيمتو", "فيمتو"},
                {"پيبسي", "بيبسي"},
                {"چيبس", "جيبس"},
                {"گاتو", "كاتو"},
                {"ژيلاتين", "زيلاتين"},
        };
        for (String[] pair : pairs) {
            assertThat(fold(pair[0])).as(pair[0]).isEqualTo(fold(pair[1]));
        }
        assertThat(fold("أحمد")).isEqualTo("احمد");
        // Each is a letter of the word, never the word break it was: ڤيمتو is not "يمتو".
        assertThat(fold("ڤيمتو")).isEqualTo("فيمتو");
        assertThat(fold("پ چ گ ژ ڤ")).isEqualTo("ب ج ك ز ف");
        assertThat(fold("Coca-Cola 1.5L")).isEqualTo("coca cola 1 5l");
        assertThat(fold("Crème brûlée, Ñandú")).isEqualTo("creme brulee nandu");
        // Nothing the fold returns can be a LIKE wildcard or an escape.
        assertThat(fold("50% off_now\\")).isEqualTo("50 off now");
        assertThat(fold("!!")).isEmpty();
    }

    @Test
    @DisplayName("the folded name is stored between spaces, and follows the name when it changes")
    void the_folded_name_follows_the_name() throws SQLException {
        assertThat(searchNameOf(renameMe.getId())).isEqualTo(" rename me ");
        execute("UPDATE products SET name = 'Za''atar Mix' WHERE id = '" + renameMe.getId() + "'");
        assertThat(searchNameOf(renameMe.getId())).isEqualTo(" zaatar mix ");
    }

    /** What the service counts its words from is the database's own fold. */
    @Test
    @DisplayName("the fold the service counts words from is search_fold itself, three terms at a time")
    void the_service_folds_with_search_fold() {
        assertThat(products.foldForSearch("Lay's", "ڤيمتو", "")).containsExactly("lays", "فيمتو", "");
        assertThat(products.foldForSearch("!!", "a.", "PEPSI  1L")).containsExactly("", "a", "pepsi 1l");
    }

    // ------------------------------------------------------------------------------------ matching

    @Test
    @DisplayName("a customer finds an Arabic, accented or apostrophised name by any spelling of it")
    void any_spelling_finds_the_name() {
        assertThat(namesNear("احمد")).containsExactly("شاي أحمد");
        assertThat(namesNear("حلوي")).containsExactly("حلوى");
        assertThat(namesNear("شوكولاته")).containsExactly("شوكولاتة كيت كات");
        assertThat(namesNear("قهوه")).containsExactly("قَهْوَة نجار");
        assertThat(namesNear("3 لتر")).containsExactly("بيبسي ٣ لتر");
        assertThat(namesNear("nescafe")).containsExactly("Nescafé Classic 200g");
        assertThat(namesNear("lays")).containsExactly("Lay's Salted");
        assertThat(namesNear("فيمتو")).containsExactly("ڤيمتو");
        assertThat(namesNear("ڤيمتو")).containsExactly("ڤيمتو");
    }

    @Test
    @DisplayName("Arabic matches as a substring, as every word, and by how it sounds")
    void arabic_tiers() {
        assertThat(tiersNear("نيدو")).containsEntry("حليب نيدو كامل الدسم", 1);
        assertThat(tiersNear("الدسم حليب")).containsEntry("حليب نيدو كامل الدسم", 2);
        assertThat(tiersNear("نيدوو")).containsEntry("حليب نيدو كامل الدسم", 3);
    }

    @Test
    @DisplayName("the better match comes first: substring, then every word, then sound")
    void latin_tiers_in_order() {
        assertThat(tiersNear("pepsi"))
                .containsEntry("Pepsi 1L", 1)
                .containsEntry("Diet Pepsi Can", 1)
                .containsEntry("Pepsi 330ml", 1);
        assertThat(tiersNear("cola coca")).containsEntry("Coca-Cola Bottle", 2);
        assertThat(tiersNear("pepsy")).containsEntry("Pepsi 1L", 3);

        List<Integer> tiers = candidates(List.of("pepsi", "cola coca"), "", HAMRA, 3, 301).stream()
                .filter(c -> mine.containsKey(c.productId()))
                .map(Candidate::tier).toList();
        assertThat(tiers).isSortedAccordingTo(Integer::compare).contains(1, 2);
    }

    /**
     * Plain word similarity reached 0.6, pg_trgm's default, whenever the first three letters agreed. The
     * strict kind compares whole words, and still forgives a typo.
     */
    @Test
    @DisplayName("sounding alike is judged on whole words: milk is not mild, but choclate is chocolate")
    void sounding_alike_is_strict() throws SQLException {
        assertThat(namesNear("milk")).containsExactly("Milk Chocolate Bar").doesNotContain("Mild Cheddar");
        assertThat(namesNear("rice")).doesNotContain("Ricotta Cheese");
        assertThat(namesNear("tuna")).doesNotContain("Tunisian Harissa");
        // What the looser rule would have let through.
        assertThat(scalar("SELECT public.word_similarity('milk', ' mild cheddar ') >= 0.6")).isEqualTo("t");
        assertThat(scalar("SELECT public.word_similarity('rice', ' ricotta cheese ') >= 0.6")).isEqualTo("t");
        assertThat(scalar("SELECT public.word_similarity('tuna', ' tunisian harissa ') >= 0.6")).isEqualTo("t");

        assertThat(tiersNear("choclate")).containsEntry("Milk Chocolate Bar", 3);
        assertThat(tiersNear("pepsy")).containsEntry("Pepsi 1L", 3);
        assertThat(tiersNear("نيدوو")).containsEntry("حليب نيدو كامل الدسم", 3);
    }

    /**
     * رز is rice, and a two-letter word: it finds the word, not every word that starts with it, and
     * "pe" is no word in this catalogue at all.
     */
    @Test
    @DisplayName("a word of two characters matches a whole word only")
    void a_two_letter_word_matches_a_whole_word() {
        assertThat(namesNear("رز")).containsExactly("رز بسمتي");
        assertThat(namesNear("pe")).isEmpty();
        assertThat(namesNear("رز بسمتي")).containsExactly("رز بسمتي");
    }

    @Test
    @DisplayName("a barcode matches exactly, in every shop that stocks it, ahead of any word")
    void barcode_first() {
        List<Candidate> found = candidates(List.of(), EAN, HAMRA, 3, 50);

        assertThat(found).extracting(c -> mine.get(c.productId()))
                .containsExactlyInAnyOrder("Pepsi 1L", "Pepsi 330ml");
        assertThat(found).allMatch(c -> c.tier() == 0);
    }

    @Test
    @DisplayName("an unused slot matches nothing, never everything")
    void an_unused_slot_matches_nothing() {
        assertThat(search.findCandidates("", "", "", "", "", "", "", false, 0, 0, 5_050d, 1.01d, NOW, 3, 50))
                .isEmpty();
    }

    // ------------------------------------------------------------------------------------ filters

    @Test
    @DisplayName("a service offer is never a candidate, near a point or not")
    void services_are_never_candidates() {
        assertThat(namesNear("pepsi flyers")).isEmpty();
        assertThat(namesEverywhere("pepsi flyers")).isEmpty();
        assertThat(namesEverywhere("pepsi")).doesNotContain("Pepsi flyers");
    }

    @Test
    @DisplayName("what cannot be bought is not a candidate: a suspended shop, a draft, out of stock")
    void what_cannot_be_bought_is_not_a_candidate() {
        List<Candidate> everywhere = candidates(List.of("pepsi"), "", null, 3, 301);

        assertThat(everywhere).noneMatch(c -> c.storeId().equals(suspendedGrocer.getId()));
        assertThat(namesEverywhere("pepsi")).doesNotContain("Pepsi Max", "Pepsi Twist");
    }

    @Test
    @DisplayName("near a point: only shops within the radius, and whose own circle reaches the point")
    void near_a_point_the_radius_and_the_shops_circle_apply() {
        List<UUID> near = storesOf(candidates(List.of("pepsi"), "", HAMRA, 3, 301));
        List<UUID> everywhere = storesOf(candidates(List.of("pepsi"), "", null, 3, 301));

        assertThat(near).contains(hamraGrocer.getId(), downtownMarket.getId())
                .doesNotContain(jouniehGrocer.getId(), smallCircle.getId());
        assertThat(everywhere).contains(jouniehGrocer.getId(), smallCircle.getId());
    }

    /**
     * Open or closed at the shop's own wall clock. Read in UTC, "Open In Beirut" would be shut: this
     * proves the zone is applied. A zone PostgreSQL reads another way than Java ("+03:00", which it
     * takes as three hours west) or not at all ("Mars/Olympus") is left for the service to judge, and
     * never fails the search.
     */
    @Test
    @DisplayName("a shop closed now is left out, read in its own zone; a zone the database cannot read is kept")
    void closed_now_is_judged_in_the_shops_zone() throws SQLException {
        List<UUID> found = storesOf(candidates(List.of("quokka"), "", HAMRA, 3, 301));

        assertThat(found).contains(openInBeirut.getId(), offsetZone.getId(), unknownZone.getId());
        assertThat(storesOf(candidates(List.of("zinger"), "", HAMRA, 3, 301)))
                .doesNotContain(zingerClosed.getId());
        assertThat(scalar("SELECT search_local_time('+03:00', now()) IS NULL")).isEqualTo("t");
        assertThat(scalar("SELECT search_local_time('EET', now()) IS NULL")).isEqualTo("t");
        assertThat(scalar("SELECT search_local_time('Mars/Olympus', now()) IS NULL")).isEqualTo("t");
        assertThat(scalar("SELECT search_local_time('Asia/Beirut', '2026-09-19 12:00:00+00')"))
                .isEqualTo("2026-09-19 15:00:00");

        // The service judges what the database kept, in the same zones Java reads.
        ItemSearchResult result = service(Duration.ofSeconds(2)).search(ItemQuery.of("quokka", null, null),
                HAMRA, 0, 10);
        assertThat(result.page().getContent()).extracting(m -> m.store().store().getName())
                .containsExactly("Open In Beirut");
    }

    // ------------------------------------------------------------------------------------ the caps

    /**
     * Twenty-four equal matches, whole words all, in six shops a block apart, and a cap of seven rows:
     * the three nearest shops are what is kept, three rows each and one for the third, whatever their
     * products' ids. Each row says the shop has four. The shop nearer than all of them is closed today
     * and takes no row.
     */
    @Test
    @DisplayName("past the cap the nearest shops survive, three rows a shop, and a closed shop takes none")
    void the_nearest_shops_survive_the_cap() {
        List<Candidate> kept = candidates(List.of("zinger cola"), "", HAMRA, 3, 7);

        assertThat(kept).hasSize(7);
        assertThat(kept).extracting(Candidate::storeId).containsExactly(
                zingerShops.get(0).getId(), zingerShops.get(0).getId(), zingerShops.get(0).getId(),
                zingerShops.get(1).getId(), zingerShops.get(1).getId(), zingerShops.get(1).getId(),
                zingerShops.get(2).getId());
        assertThat(kept).allMatch(c -> c.matchedInStore() == 4 && c.tier() == 1 && c.score() == 1.0d);

        // With no point nothing is nearer, and the better rated shops are kept instead.
        List<Candidate> rated = candidates(List.of("zinger cola"), "", null, 3, 4);
        assertThat(rated).extracting(Candidate::storeId).containsExactly(
                zingerShops.get(5).getId(), zingerShops.get(5).getId(), zingerShops.get(5).getId(),
                zingerShops.get(4).getId());
    }

    /** The service over the same rows: the nearest shops, each with its count, and truncated said. */
    @Test
    @DisplayName("the service lists the shops the cap kept, nearest first, each with all it matched")
    void the_service_over_the_cap() {
        ItemSearchService capped = new ItemSearchService(search, products, stores, storeService(),
                Clock.fixed(NOW, ZoneOffset.UTC), 5_000, 7, Duration.ofSeconds(2));

        ItemSearchResult result = capped.search(ItemQuery.of("zinger", null, null), HAMRA, 0, 10);

        assertThat(result.truncated()).isTrue();
        assertThat(result.page().getContent()).extracting(m -> m.store().store().getName())
                .containsExactly("Zinger Shop 0", "Zinger Shop 1", "Zinger Shop 2");
        assertThat(result.page().getContent()).extracting(m -> m.matchedInStore()).containsExactly(4, 4, 4);
        assertThat(result.page().getContent().get(0).items()).hasSize(3);
    }

    // ------------------------------------------------------------------------------------ the plan

    /**
     * With sequential scans switched off, the plan for a search with no point reads the trigram index.
     * Checked for both plans PostgreSQL makes: the one for the values of this search, and the generic one
     * it switches to once a statement has been prepared a few times. And for both kinds of word: one of
     * three characters or more, read by its trigrams, and one of two, read as a whole word.
     */
    @Test
    @DisplayName("with no point, the search reads the trigram index, in a custom plan and a generic one")
    void the_no_point_plan_uses_the_trigram_index() throws Exception {
        for (String mode : List.of("force_custom_plan", "force_generic_plan")) {
            for (String word : List.of("pepsi", "رز")) {
                try (Connection connection = connection(); Statement statement = connection.createStatement()) {
                    statement.execute("SET enable_seqscan = off");
                    statement.execute("SET plan_cache_mode = " + mode);
                    statement.execute(preparedCandidateQuery());
                    StringBuilder plan = new StringBuilder();
                    try (ResultSet rows = statement.executeQuery("EXPLAIN (COSTS OFF) EXECUTE cand("
                            + "'" + word + "', '" + word + "', '', '', '', '', '', false, 0, 0, 5050, 1.01, "
                            + "now(), 3, 301)")) {
                        while (rows.next()) {
                            plan.append(rows.getString(1)).append('\n');
                        }
                    }
                    assertThat(plan.toString()).as(mode + " " + word).contains("idx_products_search_name_trgm");
                }
            }
        }
    }

    /** The generic plan evaluates the patterns per execution rather than once; the answers must not change. */
    @Test
    @DisplayName("a generic plan gives the same answers as a custom one")
    void a_generic_plan_answers_the_same() throws Exception {
        for (String q : List.of("pepsi", "احمد", "نيدوو", "cola coca", "رز", "zinger cola")) {
            SearchWords words = wordsOf(q);
            List<UUID> viaRepository = candidates(List.of(q), "", HAMRA, 3, 301).stream()
                    .map(Candidate::productId).toList();
            List<UUID> generic = new ArrayList<>();
            try (Connection connection = connection(); Statement statement = connection.createStatement()) {
                statement.execute("SET plan_cache_mode = force_generic_plan");
                statement.execute(preparedCandidateQuery());
                // Literals rather than binds: EXECUTE is a utility statement, which takes none.
                try (ResultSet rows = statement.executeQuery("EXECUTE cand('" + words.phrase() + "', '"
                        + words.wordsForQuery() + "', '', '', '', '', '', true, " + HAMRA.latitude() + ", "
                        + HAMRA.longitude() + ", 5050, 1.01, '" + NOW + "', 3, 301)")) {
                    while (rows.next()) {
                        generic.add(rows.getObject(1, UUID.class));
                    }
                }
            }
            assertThat(generic).as(q).isEqualTo(viaRepository);
        }
    }

    // ------------------------------------------------------------------------------------ the shelf

    @Test
    @DisplayName("a shop's shelf searched for the same words shows what the item search found there")
    void the_shelf_matches_as_the_item_search_does() {
        assertThat(shelf("احمد")).containsExactly("شاي أحمد");
        assertThat(shelf("nescafe")).containsExactly("Nescafé Classic 200g");
        assertThat(shelf("cola coca")).containsExactly("Coca-Cola Bottle");
        assertThat(shelf("فيمتو")).containsExactly("ڤيمتو");
        // The same rules: sounding alike is strict. A two-letter word finds the whole word too, and the
        // shelf's own match on the name as typed, which it has always had, finds it inside a word.
        assertThat(shelf("milk")).containsExactly("Milk Chocolate Bar");
        assertThat(shelf("رز")).contains("رز بسمتي");
        // Best match first: the exact names, then the one that only sounds like it. Out of stock is
        // shown, as the shelf always has.
        assertThat(shelf("pepsi")).containsExactlyInAnyOrder("Pepsi 1L", "Diet Pepsi Can", "Pepsi Max");
        assertThat(shelf("pepsy")).contains("Pepsi 1L");

        SearchWords pepsi = wordsOf("pepsi");
        Page<Product> page = products.findActiveInStoreMatching(hamraGrocer.getId(), false,
                hamraGrocer.getId(), pepsi.phrase(), pepsi.wordsForQuery(), SearchPatterns.like("pepsi"),
                PageRequest.of(0, 2));
        assertThat(page.getContent()).hasSize(2);
        assertThat(page.getTotalElements()).isEqualTo(3);
    }

    // ------------------------------------------------------------------------------------ end to end

    @Test
    @DisplayName("the service groups what the database found, and lists only shops a customer can order from")
    void the_service_end_to_end() {
        ItemSearchResult result = service(Duration.ofSeconds(2)).search(ItemQuery.of("pepsi", null, null),
                HAMRA, 0, 10);

        assertThat(result.nearby()).isTrue();
        assertThat(result.page().getContent()).extracting(m -> m.store().store().getName())
                .containsExactly("Hamra Grocer", "Downtown Market");
        assertThat(result.page().getContent().get(0).items()).extracting(Product::getName)
                .containsExactlyInAnyOrder("Pepsi 1L", "Diet Pepsi Can");
        assertThat(result.page().getContent().get(1).distanceMetres()).isBetween(1_600d, 1_800d);
    }

    /** Counted as the database folds them, before the search is run. */
    @Test
    @DisplayName("a term of no word of two characters, or of six words, is refused as the database folds it")
    void the_words_are_counted_as_folded() {
        ItemSearchService service = service(Duration.ofSeconds(2));

        assertThatThrownBy(() -> service.search(ItemQuery.of("a.", null, null), HAMRA, 0, 10))
                .isInstanceOfSatisfying(SearchRefusedException.class,
                        e -> assertThat(e.getCode()).isEqualTo(ItemSearchService.SEARCH_TOO_SHORT));
        assertThatThrownBy(() -> service.search(ItemQuery.of("!!", null, null), HAMRA, 0, 10))
                .isInstanceOfSatisfying(SearchRefusedException.class,
                        e -> assertThat(e.getCode()).isEqualTo(ItemSearchService.SEARCH_TOO_SHORT));
        assertThatThrownBy(() -> service.search(ItemQuery.of("ab cd ef gh ij kl", null, null), HAMRA, 0, 10))
                .isInstanceOfSatisfying(SearchRefusedException.class,
                        e -> assertThat(e.getCode()).isEqualTo(ItemSearchService.SEARCH_TOO_MANY_WORDS));
        assertThat(service.search(ItemQuery.of("pepsi 1 l", null, null), HAMRA, 0, 10).page().getContent())
                .isNotEmpty();
    }

    /**
     * The timeout is the database's own, set in the search's transaction: a statement that runs past it
     * is cancelled with 57014, and the search says SEARCH_TIMED_OUT. A stand-in repository sleeps before
     * the candidate query, through the same connection, so the real SET LOCAL and the real driver's
     * error are what is tested.
     */
    @Test
    @DisplayName("a statement that runs past the timeout is cancelled by the database, and the search times out")
    void a_slow_statement_is_cancelled_at_the_timeout() {
        ItemSearchRepository sleepy = new ItemSearchRepository() {
            @Override
            public List<Object[]> findCandidateRows(String p1, String w1, String p2, String w2, String p3,
                                                    String w3, String barcode, boolean near, double latitude,
                                                    double longitude, double radiusMetres, double circleSlack,
                                                    Instant now, int perStore, int maxRows) {
                em.createNativeQuery("SELECT 1 FROM pg_sleep(2)").getSingleResult();
                return search.findCandidateRows(p1, w1, p2, w2, p3, w3, barcode, near, latitude, longitude,
                        radiusMetres, circleSlack, now, perStore, maxRows);
            }

            @Override
            public String limitStatementTime(String millis) {
                return search.limitStatementTime(millis);
            }
        };
        ItemSearchService service = new ItemSearchService(sleepy, products, stores, storeService(),
                Clock.fixed(NOW, ZoneOffset.UTC), 5_000, 300, Duration.ofMillis(200));

        long started = System.nanoTime();
        em.getTransaction().begin();
        try {
            assertThatThrownBy(() -> service.search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10))
                    .isInstanceOfSatisfying(SearchTimedOutException.class,
                            e -> assertThat(e.getCode()).isEqualTo(ItemSearchService.SEARCH_TIMED_OUT));
        } finally {
            em.getTransaction().rollback();
        }
        assertThat(Duration.ofNanos(System.nanoTime() - started)).isLessThan(Duration.ofMillis(1_500));
    }

    // ------------------------------------------------------------------------------------ helpers

    private Store listed(Store store, double latitude, double longitude) {
        store.pinAt(GeoPoint.of(latitude, longitude));
        store.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        store.publish(NOW.minus(Duration.ofDays(30)));
        return store;
    }

    private Product live(Store shop, String name) {
        Product product = new Product(shop.getMerchantId(), shop.getId(), name, null,
                new BigDecimal("1.50"), null);
        product.addImage("products/" + UUID.randomUUID() + ".jpg");
        product.publish();
        em.persist(product);
        mine.put(product.getId(), name);
        return product;
    }

    private StoreService storeService() {
        return new StoreService(stores, repositories.getRepository(StoreOfferRepository.class),
                repositories.getRepository(StoreFavoriteRepository.class), products,
                repositories.getRepository(CategoryRepository.class),
                new ServiceCategories(new MockEnvironment()),
                org.mockito.Mockito.mock(com.delivery.product.service.OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4));
    }

    private ItemSearchService service(Duration statementTimeout) {
        return new ItemSearchService(search, products, stores, storeService(),
                Clock.fixed(NOW, ZoneOffset.UTC), 5_000, 300, statementTimeout);
    }

    /** A term as the service hands it to the queries: folded by the database, words longest first. */
    private SearchWords wordsOf(String term) {
        return SearchWords.of(products.foldForSearch(term, "", "").get(0));
    }

    /** The candidate query for up to three terms and a barcode, around a point or everywhere. */
    private List<Candidate> candidates(List<String> terms, String barcode, GeoPoint point, int perStore,
                                       int maxRows) {
        List<SearchWords> slots = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            slots.add(i < terms.size() ? wordsOf(terms.get(i)) : SearchWords.NONE);
        }
        boolean near = point != null;
        return search.findCandidates(
                slots.get(0).phrase(), slots.get(0).wordsForQuery(),
                slots.get(1).phrase(), slots.get(1).wordsForQuery(),
                slots.get(2).phrase(), slots.get(2).wordsForQuery(),
                barcode, near,
                near ? point.latitude().doubleValue() : 0d,
                near ? point.longitude().doubleValue() : 0d,
                5_050d, 1.01d, NOW, perStore, maxRows);
    }

    private List<String> namesNear(String q) {
        return new ArrayList<>(tiersNear(q).keySet());
    }

    /** This test's products the query found around Hamra, each with its tier, best first. */
    private Map<String, Integer> tiersNear(String q) {
        Map<String, Integer> tiers = new LinkedHashMap<>();
        for (Candidate c : candidates(List.of(q), "", HAMRA, 50, 301)) {
            if (mine.containsKey(c.productId())) {
                tiers.put(mine.get(c.productId()), c.tier());
            }
        }
        return tiers;
    }

    private List<String> namesEverywhere(String q) {
        return candidates(List.of(q), "", null, 50, 301).stream()
                .filter(c -> mine.containsKey(c.productId()))
                .map(c -> mine.get(c.productId()))
                .toList();
    }

    private static List<UUID> storesOf(List<Candidate> candidates) {
        return candidates.stream().map(Candidate::storeId).distinct().toList();
    }

    private List<String> shelf(String term) {
        SearchWords words = wordsOf(term);
        return products.findActiveInStoreMatching(hamraGrocer.getId(), false, hamraGrocer.getId(),
                        words.phrase(), words.wordsForQuery(), SearchPatterns.like(term), PageRequest.of(0, 50))
                .getContent().stream().map(Product::getName).toList();
    }

    /**
     * The candidate query exactly as the repository declares it, as a PREPAREd statement, so a plan can
     * be asked of PostgreSQL itself: each {@code :name} becomes its position.
     */
    private static String preparedCandidateQuery() throws NoSuchMethodException {
        String sql = ItemSearchRepository.class.getMethod("findCandidateRows", String.class, String.class,
                        String.class, String.class, String.class, String.class, String.class, boolean.class,
                        double.class, double.class, double.class, double.class, Instant.class, int.class,
                        int.class)
                .getAnnotation(Query.class).value();
        List<String> order = List.of("p1", "w1", "p2", "w2", "p3", "w3", "barcode", "near", "latitude",
                "longitude", "radiusMetres", "circleSlack", "now", "perStore", "maxRows");
        Matcher named = Pattern.compile("(?<!:):([A-Za-z][A-Za-z0-9]*)").matcher(sql);
        StringBuilder positional = new StringBuilder();
        while (named.find()) {
            int position = order.indexOf(named.group(1)) + 1;
            assertThat(position).as(named.group(1)).isPositive();
            named.appendReplacement(positional, "\\$" + position);
        }
        named.appendTail(positional);
        return "PREPARE cand(text, text, text, text, text, text, varchar, boolean, float8, float8, float8, "
                + "float8, timestamptz, int, int) AS " + positional;
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it. products.search_name is unmapped, which validation allows.
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

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(urlInSchema(), user, password);
    }

    private String fold(String value) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement statement = connection.prepareStatement("SELECT search_fold(?)")) {
            statement.setString(1, value);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getString(1);
            }
        }
    }

    private String searchNameOf(UUID productId) throws SQLException {
        return scalar("SELECT search_name FROM products WHERE id = '" + productId + "'");
    }

    private String scalar(String sql) throws SQLException {
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
}
