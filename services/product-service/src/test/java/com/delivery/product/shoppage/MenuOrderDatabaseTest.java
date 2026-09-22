package com.delivery.product.shoppage;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.StoreCategoryService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The order a shop puts its menu in, asked of a real PostgreSQL.
 *
 * <p>Three claims a mocked repository cannot honestly make, because every one of them is about what
 * survives leaving the JVM: <em>the order the merchant dragged the items into is still there after
 * a reload</em>, <em>it belongs to one shop and not to the section next door in another one</em>,
 * and <em>the public page draws that order rather than the alphabet</em>. The sort is the database's
 * (V41's column, and the index behind it), and so is the backfill that decided what a catalogue
 * that predates the column looks like on the morning after the deploy.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a
 * schema of its own with a random name and drops only that schema.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("the menu's order, against a real database")
class MenuOrderDatabaseTest {

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "menu_order_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private ProductRepository products;
    private StoreCategoryService sections;
    private PublicShopPageService pages;

    /** Two bakeries, each with a section called Breads holding items with the same three names. */
    private Store bakery;
    private Store rival;
    private Category bakeryBreads;
    private Category rivalBreads;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    @BeforeAll
    void migrateThenSeed() throws SQLException {
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
        StoreRepository stores = repositories.getRepository(StoreRepository.class);
        products = repositories.getRepository(ProductRepository.class);
        CategoryRepository categories = repositories.getRepository(CategoryRepository.class);

        DeliveryZoneService zones = mock(DeliveryZoneService.class);
        when(zones.servedAreasOf(any())).thenReturn(List.of());
        ProductImageService images = mock(ProductImageService.class);
        when(images.resolveImage(any())).thenReturn(null);
        when(images.resolveByKey(any())).thenReturn(Map.of());
        ServiceCategories serviceCategories = mock(ServiceCategories.class);
        when(serviceCategories.enabled()).thenReturn(Set.of(Store.ServiceCategory.PRINTING));

        bakery = seeded("Boulangerie Antoine");
        rival = seeded("Boulangerie Beatrice");

        em.getTransaction().begin();
        em.persist(bakery);
        em.persist(rival);
        bakeryBreads = new Category(bakery.getId(), "Breads", null, (short) 0);
        rivalBreads = new Category(rival.getId(), "Breads", null, (short) 0);
        em.persist(bakeryBreads);
        em.persist(rivalBreads);
        // Named so the alphabet and the merchant's order can visibly disagree, and stocked
        // identically in both shops so "per shop" is a claim with something to fail against.
        for (Store shop : List.of(bakery, rival)) {
            UUID section = shop == bakery ? bakeryBreads.getId() : rivalBreads.getId();
            for (String name : List.of("Croissant", "Knefe", "Manouche")) {
                Product item = new Product("merchant-" + shop.getName().hashCode(), shop.getId(),
                        name, name + " from " + shop.getName(), new BigDecimal("2.50"), section);
                item.addImage("stores/x/" + UUID.randomUUID() + ".jpg");
                item.publish();
                em.persist(item);
            }
        }
        em.getTransaction().commit();
        em.clear();

        sections = new StoreCategoryService(categories, products);
        pages = new PublicShopPageService(stores, products, categories, zones, images,
                serviceCategories,
                Clock.fixed(Instant.parse("2026-09-20T15:00:00Z"), ZoneId.of("UTC")),
                Duration.ofHours(4), new BigDecimal("90000"));
    }

    private Store seeded(String name) {
        Store shop = new Store("merchant-" + name.hashCode(), name, Store.Vertical.GROCERY);
        shop.useTimezone("Asia/Beirut");
        shop.replaceHours(List.of(
                new StoreHours(DayOfWeek.MONDAY, LocalTime.of(6, 0), LocalTime.of(20, 0)),
                new StoreHours(DayOfWeek.SUNDAY, LocalTime.of(6, 0), LocalTime.of(20, 0))));
        shop.pinAt(GeoPoint.of(33.8905, 35.4788));
        shop.publish(Instant.parse("2026-01-05T09:00:00Z"));
        return shop;
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

    // ---------------------------------------------------------------- the order

    @Test
    @DisplayName("the order a merchant drags survives a reload, and belongs to one shop")
    void theOrderSurvivesAReloadAndIsPerShop() {
        List<Product> before = itemsOf(bakery, bakeryBreads);
        // Whatever the shop next door is in right now, which is deliberately not asserted to be
        // anything in particular: these tests share one schema, and a claim about the neighbour's
        // absolute order would be a claim about which test ran first.
        List<String> neighbourBefore = names(itemsOf(rival, rivalBreads));

        // Knefe to the top, which the alphabet would never do.
        em.getTransaction().begin();
        sections.reorderProducts(bakery.getId(), bakeryBreads.getId(),
                List.of(before.get(1).getId(), before.get(2).getId(), before.get(0).getId()));
        em.getTransaction().commit();
        // Everything read after this comes from the database, not from the persistence context
        // that did the writing — which is the whole of what "survives a reload" means here.
        em.clear();

        assertThat(names(itemsOf(bakery, bakeryBreads)))
                .containsExactly(before.get(1).getName(), before.get(2).getName(),
                        before.get(0).getName());
        assertThat(names(itemsOf(rival, rivalBreads)))
                .as("the shop next door has its own Breads, with the same three names, untouched")
                .containsExactlyElementsOf(neighbourBefore);

        // Read from the column rather than through the sort, or this would prove the ORDER BY and
        // not the write: a reorder rewrites 0..n-1, which is what keeps the sequence from drifting
        // into ties after a few drags.
        assertThat(em.createNativeQuery(
                        "SELECT count(DISTINCT position) FROM products WHERE store_id = :store "
                                + "AND category_id = :section")
                .setParameter("store", bakery.getId())
                .setParameter("section", bakeryBreads.getId())
                .getSingleResult())
                .as("three items, three distinct positions")
                .isEqualTo(3L);
    }

    @Test
    @DisplayName("the public page draws the shop's order, not the alphabet")
    void thePageDrawsTheMerchantsOrder() {
        List<Product> items = itemsOf(rival, rivalBreads);
        em.getTransaction().begin();
        sections.reorderProducts(rival.getId(), rivalBreads.getId(),
                List.of(items.get(2).getId(), items.get(0).getId(), items.get(1).getId()));
        em.getTransaction().commit();
        em.clear();

        PublicShopPage.Section drawn = pages.read(rival.getSlug()).catalogue().sections().get(0);
        assertThat(drawn.name()).isEqualTo("Breads");
        assertThat(drawn.items().stream().map(PublicShopPage.Item::name))
                .containsExactly("Manouche", "Croissant", "Knefe");
    }

    @Test
    @DisplayName("an item taken off the shelf leaves the page, and putting it back returns it in place")
    void theAvailabilitySwitchReachesThePage() {
        List<Product> items = itemsOf(bakery, bakeryBreads);
        Product middle = items.get(1);
        List<String> whole = names(items);

        // What the builder's switch sends for a goods product: archive to take it off sale,
        // publish to put it back. Nothing else on the platform means "not on the shelf".
        em.getTransaction().begin();
        em.find(Product.class, middle.getId()).archive();
        em.getTransaction().commit();
        em.clear();

        assertThat(pageItemsOf(bakery))
                .as("the page is the customer's, and a withdrawn item is not on it")
                .doesNotContain(middle.getName())
                .hasSize(whole.size() - 1);

        em.getTransaction().begin();
        em.find(Product.class, middle.getId()).publish();
        em.getTransaction().commit();
        em.clear();

        assertThat(pageItemsOf(bakery))
                .as("and it comes back where the merchant left it, not at the bottom")
                .containsExactlyElementsOf(whole);
    }

    @Test
    @DisplayName("the section next door's items cannot be dragged into this shop's order")
    void anotherShopsItemsAreRefused() {
        List<UUID> theirs = itemsOf(rival, rivalBreads).stream().map(Product::getId).toList();
        assertThatThrownBy(() -> sections.reorderProducts(bakery.getId(), bakeryBreads.getId(),
                theirs))
                .isInstanceOf(RuntimeException.class);
        assertThatThrownBy(() -> sections.reorderProducts(bakery.getId(), rivalBreads.getId(),
                theirs))
                .as("and neither is the other shop's section a thing this shop may arrange")
                .isInstanceOf(RuntimeException.class);
    }

    private List<Product> itemsOf(Store shop, Category section) {
        return products.findByStoreIdAndCategoryIdOrderByPositionAscNameAsc(
                shop.getId(), section.getId());
    }

    private static List<String> names(List<Product> items) {
        return items.stream().map(Product::getName).toList();
    }

    private List<String> pageItemsOf(Store shop) {
        return pages.read(shop.getSlug()).catalogue().sections().get(0).items().stream()
                .map(PublicShopPage.Item::name)
                .toList();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(
                url + (url.contains("?") ? "&" : "?") + "currentSchema=" + schema, user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
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
