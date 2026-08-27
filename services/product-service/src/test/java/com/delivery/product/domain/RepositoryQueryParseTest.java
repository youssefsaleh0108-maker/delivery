package com.delivery.product.domain;

import java.util.Map;

import org.hibernate.SessionFactory;
import org.hibernate.cfg.Configuration;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * Every hand-written query in this service parses against the real mappings.
 *
 * <p>This exists because of where the alternative failure lands. A typo in a {@code @Query} is not a
 * compile error and not a test failure — Spring Data validates annotated queries when it builds the
 * repository, so the first symptom is the whole service refusing to start, in whatever environment
 * it was deployed to next. Parsing them here moves that discovery from a failed deploy to a failed
 * build.
 *
 * <p>Hibernate is booted with no database at all: an explicit dialect and
 * {@code allow_jdbc_metadata_access=false} mean nothing connects, and {@code createQuery} only ever
 * parses. So this checks exactly what it claims to — that the HQL is well formed and every path in
 * it resolves against the entity model — and deliberately not that the results are right, which is
 * what the service tests are for.
 *
 * <p>Native SQL is out of scope and cannot be otherwise: {@code StoreRepository.findActiveIdsNear}
 * calls PostGIS functions that only exist inside Postgres, and nothing short of a real database can
 * check it. That gap is real and is called out in this service's notes.
 */
@DisplayName("the queries this service declares")
class RepositoryQueryParseTest {

    private static SessionFactory sessionFactory;

    @BeforeAll
    static void bootHibernateWithoutADatabase() {
        Configuration configuration = new Configuration()
                .addAnnotatedClass(Banner.class)
                .addAnnotatedClass(Category.class)
                .addAnnotatedClass(DeliveredOrderLine.class)
                .addAnnotatedClass(DeliveryZone.class)
                .addAnnotatedClass(GeocodeCacheEntry.class)
                .addAnnotatedClass(Product.class)
                .addAnnotatedClass(ProductOption.class)
                .addAnnotatedClass(ProductOptionGroup.class)
                .addAnnotatedClass(ReviewableOrder.class)
                .addAnnotatedClass(Store.class)
                .addAnnotatedClass(StoreDeliveryZone.class)
                .addAnnotatedClass(StoreFavorite.class)
                .addAnnotatedClass(StoreHours.class)
                .addAnnotatedClass(StoreOffer.class)
                .addAnnotatedClass(StoreReview.class);

        configuration.addProperties(asProperties(Map.of(
                // Named rather than discovered, because discovery is what would need a connection.
                "hibernate.dialect", "org.hibernate.dialect.PostgreSQLDialect",
                "hibernate.boot.allow_jdbc_metadata_access", "false",
                "hibernate.temp.use_jdbc_metadata_defaults", "false",
                "hibernate.hbm2ddl.auto", "none",
                "hibernate.default_schema", "product")));

        sessionFactory = configuration.buildSessionFactory();
    }

    @AfterAll
    static void close() {
        if (sessionFactory != null) {
            sessionFactory.close();
        }
    }

    private static java.util.Properties asProperties(Map<String, String> values) {
        java.util.Properties properties = new java.util.Properties();
        properties.putAll(values);
        return properties;
    }

    private void parses(String hql) {
        assertThatCode(() -> sessionFactory.openStatelessSession().createQuery(hql, Object[].class))
                .as(hql)
                .doesNotThrowAnyException();
    }

    /** Same check for a DELETE or UPDATE, which Hibernate refuses to hand a result type. */
    private void parsesMutation(String hql) {
        assertThatCode(() -> sessionFactory.openStatelessSession().createMutationQuery(hql))
                .as(hql)
                .doesNotThrowAnyException();
    }

    /**
     * The co-occurrence query behind the cross-sell rail.
     *
     * <p>The riskiest one in the service: an entity self-join with an explicit {@code ON}, a
     * {@code COUNT(DISTINCT ...)} repeated in the select, the {@code HAVING} and the {@code ORDER
     * BY}. Kept character-for-character in step with the repository — if the two drift, this stops
     * proving anything about the query that actually runs.
     */
    @Test
    void the_cross_sell_co_occurrence_query_parses() {
        parses("""
                SELECT other.productId, COUNT(DISTINCT other.orderId)
                FROM DeliveredOrderLine mine
                JOIN DeliveredOrderLine other ON other.orderId = mine.orderId
                WHERE mine.productId = :productId
                  AND other.productId <> :productId
                  AND other.storeId = mine.storeId
                GROUP BY other.productId
                HAVING COUNT(DISTINCT other.orderId) >= :minOrdersTogether
                ORDER BY COUNT(DISTINCT other.orderId) DESC, other.productId ASC
                """);
    }

    @Test
    void the_geocode_cache_eviction_query_parses() {
        parsesMutation("DELETE FROM GeocodeCacheEntry e WHERE e.fetchedAt < :cutoff");
    }

    /**
     * The two storefront queries, parsed here as well because they were previously only ever
     * exercised by starting the service.
     */
    @Test
    void the_storefront_queries_parse() {
        parses("""
                SELECT s FROM Store s
                WHERE s.status = :status
                  AND (:vertical IS NULL OR s.vertical = :vertical)
                  AND (LOWER(s.name) LIKE :search)
                  AND (:maxDeliveryFee IS NULL OR s.deliveryFee <= :maxDeliveryFee)
                  AND (:maxEtaMinutes IS NULL OR s.etaMaxMinutes <= :maxEtaMinutes)
                  AND (:minRating IS NULL OR s.rating >= :minRating)
                """);

        parses("""
                SELECT s FROM Store s
                JOIN StoreFavorite f ON f.id.storeId = s.id
                WHERE f.id.userId = :userId
                  AND s.status = :status
                ORDER BY f.createdAt DESC
                """);
    }

    /** Every mapped column of the new entities resolves — the cheapest guard against a typo. */
    @Test
    void the_new_projections_are_mapped_as_the_migrations_declare_them() {
        parses("""
                SELECT l.orderId, l.productId, l.storeId, l.qty, l.deliveredAt
                FROM DeliveredOrderLine l
                """);

        parses("""
                SELECT e.id, e.provider, e.lookup, e.cacheKey, e.payload, e.fetchedAt, e.hitCount
                FROM GeocodeCacheEntry e
                """);

        parses("SELECT s.id, s.latitude, s.longitude, s.address FROM Store s");
    }
}
