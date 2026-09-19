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
import com.delivery.product.service.SearchPatterns;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * V37 and the item search's SQL, against a real PostgreSQL with PostGIS and pg_trgm.
 *
 * <p>The customer item search matches words in SQL: the fold ({@code search_fold}), the tiers, the
 * trigram index and the filters that keep services, drafts and far shops out
 * ({@link ItemSearchRepository#findCandidateRows}). Nothing short of a database can check any of that,
 * and the service's own tests stand a Java copy in for it. So this migrates a schema from empty to the
 * latest version, validates every entity against it as the service does at boot, and asks the real
 * queries.
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
        };
        for (String[] pair : pairs) {
            assertThat(fold(pair[0])).as(pair[0]).isEqualTo(fold(pair[1]));
        }
        assertThat(fold("أحمد")).isEqualTo("احمد");
        assertThat(fold("Coca-Cola 1.5L")).isEqualTo("coca cola 1 5l");
        assertThat(fold("Crème brûlée, Ñandú")).isEqualTo("creme brulee nandu");
        // Nothing the fold returns can be a LIKE wildcard or an escape.
        assertThat(fold("50% off_now\\")).isEqualTo("50 off now");
        assertThat(fold("!!")).isEmpty();
    }

    @Test
    @DisplayName("the folded name is stored, and follows the name when it changes")
    void the_folded_name_follows_the_name() throws SQLException {
        assertThat(searchNameOf(renameMe.getId())).isEqualTo("rename me");
        execute("UPDATE products SET name = 'Za''atar Mix' WHERE id = '" + renameMe.getId() + "'");
        assertThat(searchNameOf(renameMe.getId())).isEqualTo("zaatar mix");
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

        List<Candidate> ranked = search.findCandidates("pepsi", "cola coca", "", "", true,
                HAMRA.latitude().doubleValue(), HAMRA.longitude().doubleValue(), 5_050d, 1.01d, 50);
        List<Integer> tiers = ranked.stream().filter(c -> mine.containsKey(c.productId()))
                .map(Candidate::tier).toList();
        assertThat(tiers).isSortedAccordingTo(Integer::compare).contains(1, 2);
    }

    @Test
    @DisplayName("a barcode matches exactly, in every shop that stocks it, ahead of any word")
    void barcode_first() {
        List<Candidate> found = search.findCandidates("", "", "", EAN, true,
                HAMRA.latitude().doubleValue(), HAMRA.longitude().doubleValue(), 5_050d, 1.01d, 50);

        assertThat(found).extracting(c -> mine.get(c.productId()))
                .containsExactlyInAnyOrder("Pepsi 1L", "Pepsi 330ml");
        assertThat(found).allMatch(c -> c.tier() == 0);
    }

    @Test
    @DisplayName("a term that folds to nothing matches nothing, never everything")
    void punctuation_matches_nothing() {
        assertThat(search.findCandidates("!!", "", "", "", false, 0, 0, 5_050d, 1.01d, 50)).isEmpty();
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
        List<Candidate> everywhere = search.findCandidates("pepsi", "", "", "", false, 0, 0,
                5_050d, 1.01d, 100);

        assertThat(everywhere).noneMatch(c -> c.storeId().equals(suspendedGrocer.getId()));
        assertThat(namesEverywhere("pepsi")).doesNotContain("Pepsi Max", "Pepsi Twist");
    }

    @Test
    @DisplayName("near a point: only shops within the radius, and whose own circle reaches the point")
    void near_a_point_the_radius_and_the_shops_circle_apply() {
        List<UUID> near = storesOf(search.findCandidates("pepsi", "", "", "", true,
                HAMRA.latitude().doubleValue(), HAMRA.longitude().doubleValue(), 5_050d, 1.01d, 100));
        List<UUID> everywhere = storesOf(search.findCandidates("pepsi", "", "", "", false, 0, 0,
                5_050d, 1.01d, 100));

        assertThat(near).contains(hamraGrocer.getId(), downtownMarket.getId())
                .doesNotContain(jouniehGrocer.getId(), smallCircle.getId());
        assertThat(everywhere).contains(jouniehGrocer.getId(), smallCircle.getId());
    }

    // ------------------------------------------------------------------------------------ the plan

    /**
     * With sequential scans switched off, the plan for a search with no point reads the trigram index.
     * Checked for both plans PostgreSQL makes: the one for the values of this search, and the generic one
     * it switches to once a statement has been prepared a few times.
     */
    @Test
    @DisplayName("with no point, the search reads the trigram index, in a custom plan and a generic one")
    void the_no_point_plan_uses_the_trigram_index() throws Exception {
        for (String mode : List.of("force_custom_plan", "force_generic_plan")) {
            try (Connection connection = connection(); Statement statement = connection.createStatement()) {
                statement.execute("SET enable_seqscan = off");
                statement.execute("SET plan_cache_mode = " + mode);
                statement.execute(preparedCandidateQuery());
                StringBuilder plan = new StringBuilder();
                try (ResultSet rows = statement.executeQuery("EXPLAIN (COSTS OFF) EXECUTE cand("
                        + "'pepsi', '', '', '', false, 0, 0, 5050, 1.01, 301)")) {
                    while (rows.next()) {
                        plan.append(rows.getString(1)).append('\n');
                    }
                }
                assertThat(plan.toString()).as(mode).contains("idx_products_search_name_trgm");
            }
        }
    }

    /** The generic plan evaluates the fold per row rather than once; the answers must not change. */
    @Test
    @DisplayName("a generic plan gives the same answers as a custom one")
    void a_generic_plan_answers_the_same() throws Exception {
        for (String q : List.of("pepsi", "احمد", "نيدوو", "cola coca", "!!")) {
            List<UUID> viaRepository = search.findCandidates(q, "", "", "", true,
                            HAMRA.latitude().doubleValue(), HAMRA.longitude().doubleValue(), 5_050d, 1.01d, 301)
                    .stream().map(Candidate::productId).toList();
            List<UUID> generic = new ArrayList<>();
            try (Connection connection = connection(); Statement statement = connection.createStatement()) {
                statement.execute("SET plan_cache_mode = force_generic_plan");
                statement.execute(preparedCandidateQuery());
                // Literals rather than binds: EXECUTE is a utility statement, which takes none.
                try (ResultSet rows = statement.executeQuery("EXECUTE cand('" + q.replace("'", "''")
                        + "', '', '', '', true, " + HAMRA.latitude() + ", " + HAMRA.longitude()
                        + ", 5050, 1.01, 301)")) {
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
        // Best match first: the exact names, then the one that only sounds like it. Out of stock is
        // shown, as the shelf always has.
        assertThat(shelf("pepsi")).containsExactlyInAnyOrder("Pepsi 1L", "Diet Pepsi Can", "Pepsi Max");
        assertThat(shelf("pepsy")).contains("Pepsi 1L");

        Page<Product> page = products.findActiveInStoreMatching(hamraGrocer.getId(), false,
                hamraGrocer.getId(), "pepsi", SearchPatterns.like("pepsi"), PageRequest.of(0, 2));
        assertThat(page.getContent()).hasSize(2);
        assertThat(page.getTotalElements()).isEqualTo(3);
    }

    // ------------------------------------------------------------------------------------ end to end

    @Test
    @DisplayName("the service groups what the database found, and lists only shops a customer can order from")
    void the_service_end_to_end() {
        ItemSearchService service = new ItemSearchService(search, products, stores,
                new StoreService(stores, repositories.getRepository(StoreOfferRepository.class),
                        repositories.getRepository(StoreFavoriteRepository.class), products,
                        repositories.getRepository(CategoryRepository.class),
                        new ServiceCategories(new MockEnvironment()),
                        org.mockito.Mockito.mock(
                                com.delivery.product.service.OnboardingApplicationClient.class),
                        Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4)),
                Clock.fixed(NOW, ZoneOffset.UTC), 5_000, 300);

        ItemSearchResult result = service.search(ItemQuery.of("pepsi", null, null), HAMRA, 0, 10);

        assertThat(result.nearby()).isTrue();
        assertThat(result.page().getContent()).extracting(m -> m.store().store().getName())
                .containsExactly("Hamra Grocer", "Downtown Market");
        assertThat(result.page().getContent().get(0).items()).extracting(Product::getName)
                .containsExactlyInAnyOrder("Pepsi 1L", "Diet Pepsi Can");
        assertThat(result.page().getContent().get(1).distanceMetres()).isBetween(1_600d, 1_800d);
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

    private List<String> namesNear(String q) {
        return new ArrayList<>(tiersNear(q).keySet());
    }

    /** This test's products the query found around Hamra, each with its tier, best first. */
    private Map<String, Integer> tiersNear(String q) {
        Map<String, Integer> tiers = new LinkedHashMap<>();
        for (Candidate c : search.findCandidates(q, "", "", "", true, HAMRA.latitude().doubleValue(),
                HAMRA.longitude().doubleValue(), 5_050d, 1.01d, 301)) {
            if (mine.containsKey(c.productId())) {
                tiers.put(mine.get(c.productId()), c.tier());
            }
        }
        return tiers;
    }

    private List<String> namesEverywhere(String q) {
        return search.findCandidates(q, "", "", "", false, 0, 0, 5_050d, 1.01d, 301).stream()
                .filter(c -> mine.containsKey(c.productId()))
                .map(c -> mine.get(c.productId()))
                .toList();
    }

    private static List<UUID> storesOf(List<Candidate> candidates) {
        return candidates.stream().map(Candidate::storeId).distinct().toList();
    }

    private List<String> shelf(String term) {
        return products.findActiveInStoreMatching(hamraGrocer.getId(), false, hamraGrocer.getId(),
                        term, SearchPatterns.like(term), PageRequest.of(0, 50))
                .getContent().stream().map(Product::getName).toList();
    }

    /**
     * The candidate query exactly as the repository declares it, as a PREPAREd statement, so a plan can
     * be asked of PostgreSQL itself: each {@code :name} becomes its position.
     */
    private static String preparedCandidateQuery() throws NoSuchMethodException {
        String sql = ItemSearchRepository.class.getMethod("findCandidateRows", String.class, String.class,
                        String.class, String.class, boolean.class, double.class, double.class, double.class,
                        double.class, int.class)
                .getAnnotation(Query.class).value();
        List<String> order = List.of("t1", "t2", "t3", "barcode", "near", "latitude", "longitude",
                "radiusMetres", "circleSlack", "maxRows");
        Matcher named = Pattern.compile("(?<!:):([A-Za-z][A-Za-z0-9]*)").matcher(sql);
        StringBuilder positional = new StringBuilder();
        while (named.find()) {
            int position = order.indexOf(named.group(1)) + 1;
            assertThat(position).as(named.group(1)).isPositive();
            named.appendReplacement(positional, "\\$" + position);
        }
        named.appendTail(positional);
        return "PREPARE cand(text, text, text, varchar, boolean, float8, float8, float8, float8, int) AS "
                + positional;
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
