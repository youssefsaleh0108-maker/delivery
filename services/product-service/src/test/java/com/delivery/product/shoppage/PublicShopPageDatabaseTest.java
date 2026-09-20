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

import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.DeliveryZoneService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.shoppage.PublicShopPageService.ShopPageNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Which shops have a public page, asked of a real PostgreSQL.
 *
 * <p>The rule is the sharpest one this feature has — <em>a shop that is not live, or has no pin,
 * must be indistinguishable from a slug that never existed</em> — and it is the one a mocked
 * repository cannot honestly check. Here five shops in five states sit in the same table, and the
 * page read and the sitemap read are both resolved by the database: the slug lookup is Spring
 * Data's derived query, whose exact-match and case semantics only a database decides, and the
 * sitemap's list is a scan over rows that really do include a draft and a suspended shop.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a
 * schema of its own with a random name and drops only that schema.
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("which shops have a public page, against a real database")
class PublicShopPageDatabaseTest {

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "shop_page_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private PublicShopPageService pages;

    private Store live;
    private Store draft;
    private Store suspended;
    private Store pinless;
    private Store closedCategoryProvider;

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
        ProductRepository products = repositories.getRepository(ProductRepository.class);
        CategoryRepository categories = repositories.getRepository(CategoryRepository.class);

        DeliveryZoneService zones = mock(DeliveryZoneService.class);
        when(zones.servedAreasOf(any())).thenReturn(List.of());
        ProductImageService images = mock(ProductImageService.class);
        when(images.resolveImage(any())).thenReturn(null);
        when(images.resolveByKey(any())).thenReturn(Map.of());
        ServiceCategories serviceCategories = mock(ServiceCategories.class);
        // Printing is open; photography is not — which is what makes the provider below invisible.
        when(serviceCategories.enabled()).thenReturn(Set.of(Store.ServiceCategory.PRINTING));

        live = seeded("Dekkanet Al Rawche", Store.Vertical.GROCERY, null, true, true);
        draft = seeded("Draft Corner Shop", Store.Vertical.GROCERY, null, false, true);
        suspended = seeded("Suspended Grocer", Store.Vertical.GROCERY, null, true, true);
        suspended.suspend();
        // Listed while it had a pin, and unpinned afterwards — which Store.publish allows, and is
        // exactly the shop this page must not draw.
        pinless = seeded("Pinless Bakery", Store.Vertical.GROCERY, null, true, true);
        pinless.clearPin();
        closedCategoryProvider = seeded("Rawche Photo Studio", Store.Vertical.SERVICES,
                Store.ServiceCategory.PHOTOGRAPHY, true, true);

        em.getTransaction().begin();
        for (Store shop : List.of(live, draft, suspended, pinless, closedCategoryProvider)) {
            em.persist(shop);
        }
        em.getTransaction().commit();
        em.clear();

        pages = new PublicShopPageService(stores, products, categories, zones, images,
                serviceCategories,
                Clock.fixed(Instant.parse("2026-09-20T15:00:00Z"), ZoneId.of("UTC")),
                Duration.ofHours(4), new BigDecimal("90000"));
    }

    private Store seeded(String name, Store.Vertical vertical, Store.ServiceCategory category,
                         boolean listed, boolean pinned) {
        Store shop = vertical == Store.Vertical.SERVICES
                ? new Store("merchant-" + name.hashCode(), name, vertical, category)
                : new Store("merchant-" + name.hashCode(), name, vertical);
        shop.useTimezone("Asia/Beirut");
        shop.replaceHours(List.of(
                new StoreHours(DayOfWeek.MONDAY, LocalTime.of(8, 0), LocalTime.of(23, 0)),
                new StoreHours(DayOfWeek.SUNDAY, LocalTime.of(8, 0), LocalTime.of(23, 0))));
        if (pinned) {
            shop.pinAt(GeoPoint.of(33.8905, 35.4788));
        }
        if (listed) {
            shop.publish(Instant.parse("2026-01-05T09:00:00Z"));
        }
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

    @Test
    @DisplayName("the live, pinned shop is the only one with a page")
    void onlyTheLivePinnedShopRenders() {
        assertThat(pages.read(live.getSlug()).name()).isEqualTo("Dekkanet Al Rawche");

        for (Store hidden : List.of(draft, suspended, pinless, closedCategoryProvider)) {
            assertThatThrownBy(() -> pages.read(hidden.getSlug()))
                    .as("%s must be as absent as a slug nobody has ever had", hidden.getName())
                    .isInstanceOf(ShopPageNotFoundException.class);
        }
        assertThatThrownBy(() -> pages.read("a-slug-that-never-existed-0000ffff"))
                .isInstanceOf(ShopPageNotFoundException.class);
    }

    @Test
    @DisplayName("the sitemap offers a crawler exactly the pages that exist")
    void theSitemapAgreesWithThePage() {
        List<String> listed = pages.listedSlugs();

        assertThat(listed).contains(live.getSlug());
        assertThat(listed).doesNotContain(draft.getSlug(), suspended.getSlug(),
                pinless.getSlug(), closedCategoryProvider.getSlug());
        // The strongest form of the promise, over every row the migrations also seeded (V12 and
        // V39 open a demo storefront): every address the sitemap offers renders.
        for (String slug : listed) {
            assertThat(pages.read(slug).slug()).isEqualTo(slug);
        }
    }

    @Test
    @DisplayName("an id is not a slug: the page has one address, not two")
    void anIdIsNotASlug() {
        assertThatThrownBy(() -> pages.read(live.getId().toString()))
                .isInstanceOf(ShopPageNotFoundException.class);
    }

    @Test
    @DisplayName("the slug is matched exactly: no case-folded second address for the same shop")
    void theSlugIsMatchedExactly() {
        assertThatThrownBy(() -> pages.read(live.getSlug().toUpperCase(java.util.Locale.ROOT)))
                .isInstanceOf(ShopPageNotFoundException.class);
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
