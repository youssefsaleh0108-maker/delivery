package com.delivery.product.domain;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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

import com.delivery.product.service.DeliveryZoneService;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The areas a shop page's "Delivery area" map lists, against a real PostgreSQL.
 *
 * <p>The list is read by a derived query no other test can check — Spring Data builds it from the
 * method's name, and only a database says what order it answers in — and it carries a promise a mock
 * cannot keep honestly: that it is exactly the set of areas order placement serves. Here both are
 * read from the same tables, so a retired area, an area nobody placed on the map, and an area two
 * shops rank the same are each answered by the real rows.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a schema
 * of its own with a random name and drops only that schema (see {@code ServicesVerticalDatabaseTest}).
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("a shop's delivery areas, against a real database")
class DeliveryAreaDatabaseTest {

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "delivery_area_it_" + UUID.randomUUID().toString().substring(0, 8);

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private DeliveryZoneRepository zones;
    private DeliveryZoneService service;

    private Store grocer;
    private Store kitchen;
    private List<DeliveryZone> register;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    @BeforeAll
    void migrateThenSeed() throws SQLException {
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
                .locations("classpath:db/migration/shared", "classpath:db/migration/product")
                .outOfOrder(true)
                .load()
                .migrate();

        entityManagerFactory = entityManagerFactory();
        em = entityManagerFactory.createEntityManager();
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(em);
        zones = repositories.getRepository(DeliveryZoneRepository.class);
        StoreDeliveryZoneRepository storeZones =
                repositories.getRepository(StoreDeliveryZoneRepository.class);
        service = new DeliveryZoneService(zones, storeZones, 5_000);

        // Ranked by the back office: two areas share rank 10, so their names decide between them.
        DeliveryZone verdun = placed(new DeliveryZone("Verdun", "Beirut", 20), 33.8870d, 35.4830d);
        DeliveryZone hamra = placed(new DeliveryZone("Hamra", "Beirut", 10), 33.8960d, 35.4800d);
        DeliveryZone achrafieh = new DeliveryZone("Achrafieh", "Beirut", 10);
        DeliveryZone jounieh = placed(new DeliveryZone("Jounieh", "Keserwan", 5), 33.9800d, 35.6180d);
        DeliveryZone rasBeirut = placed(new DeliveryZone("Ras Beirut", "Beirut", 30), 33.9010d, 35.4730d);
        rasBeirut.retire();

        grocer = new Store("merchant-grocer", "Hamra Corner Grocer", Store.Vertical.GROCERY);
        kitchen = new Store("merchant-kitchen", "Smoke Test Kitchen", Store.Vertical.RESTAURANT);

        em.getTransaction().begin();
        for (DeliveryZone zone : List.of(verdun, hamra, achrafieh, jounieh, rasBeirut)) {
            em.persist(zone);
        }
        em.persist(grocer);
        em.persist(kitchen);
        em.flush();
        // Priced before Ras Beirut was retired, as a real shop's row would have been. Jounieh is
        // the one area the grocer does not go to.
        for (DeliveryZone zone : List.of(verdun, hamra, achrafieh, rasBeirut)) {
            em.persist(new StoreDeliveryZone(grocer.getId(), zone.getId(), new BigDecimal("2.00"),
                    null, 0));
        }
        em.getTransaction().commit();
        em.clear();

        register = zones.findAllByOrderBySortOrderAscNameAsc();
    }

    private static DeliveryZone placed(DeliveryZone zone, double latitude, double longitude) {
        zone.placeAt(GeoPoint.of(latitude, longitude));
        return zone;
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
    @DisplayName("lists the shop's areas in the picker's order, the retired and the unplaced included")
    void lists_the_shops_areas_in_picker_order() {
        List<DeliveryZone> served = service.servedAreasOf(grocer.getId());

        assertThat(served).extracting(DeliveryZone::getName)
                .containsExactly("Achrafieh", "Hamra", "Verdun", "Ras Beirut");
        assertThat(served).filteredOn(zone -> zone.getName().equals("Achrafieh"))
                .singleElement()
                .satisfies(zone -> assertThat(zone.centre()).isNull());
        assertThat(served).filteredOn(zone -> zone.getName().equals("Hamra"))
                .singleElement()
                .satisfies(zone -> assertThat(zone.getCenterLat()).isEqualByComparingTo("33.896"));
    }

    @Test
    @DisplayName("is exactly the set of areas order placement serves, area by area")
    void is_exactly_what_placement_serves() {
        List<UUID> served = service.servedAreasOf(grocer.getId()).stream()
                .map(DeliveryZone::getId).toList();
        Store read = em.find(Store.class, grocer.getId());

        assertThat(register).hasSize(5);
        for (DeliveryZone zone : register) {
            assertThat(service.termsFor(read, zone.getId()).served())
                    .as("checkout serves %s exactly when the map lists it", zone.getName())
                    .isEqualTo(served.contains(zone.getId()));
        }
    }

    @Test
    @DisplayName("a shop that prices no area lists none, and placement serves it everywhere")
    void no_areas_lists_none() {
        Store read = em.find(Store.class, kitchen.getId());

        assertThat(service.servedAreasOf(kitchen.getId())).isEmpty();
        for (DeliveryZone zone : register) {
            assertThat(service.termsFor(read, zone.getId()).served()).isTrue();
        }
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(
                url + (url.contains("?") ? "&" : "?") + "currentSchema=" + schema, user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it.
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
