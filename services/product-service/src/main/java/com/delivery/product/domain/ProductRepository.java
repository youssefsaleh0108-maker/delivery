package com.delivery.product.domain;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProductRepository extends JpaRepository<Product, UUID> {

    /** The Merchant Portal's list — everything the merchant owns, any status. */
    Page<Product> findByMerchantId(String merchantId, Pageable pageable);

    Optional<Product> findByIdAndMerchantId(UUID id, String merchantId);

    /**
     * The customer-facing catalog. ACTIVE only, optionally filtered by category and name.
     *
     * <p>{@code namePattern} is always a non-null LIKE pattern ({@code %} when unfiltered) rather
     * than a nullable search term. A null String parameter inside {@code LOWER()} has no inferable
     * type, so the driver binds it as {@code bytea} and Postgres fails the whole query with
     * "function lower(bytea) does not exist". Callers should use
     * {@link com.delivery.product.service.CatalogService#browseCatalog} rather than building the
     * pattern by hand.
     *
     * <p>{@code categoryId} stays null-tolerant: it is only ever compared to a typed column, so
     * Postgres infers uuid from the other side of the equality.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND (:categoryId IS NULL OR p.categoryId = :categoryId)
              AND LOWER(p.name) LIKE :namePattern ESCAPE '\\'
            """)
    Page<Product> findActiveCatalog(@Param("categoryId") UUID categoryId,
                                    @Param("namePattern") String namePattern,
                                    Pageable pageable);

    long countByCategoryId(UUID categoryId);

    /**
     * A store's shelf: the ACTIVE products in one store, optionally narrowed to one aisle.
     *
     * <p>The store landing page's main query, and the reason V11 adds a partial index on
     * {@code (store_id, category_id)}. Same non-null LIKE pattern contract as
     * {@link #findActiveCatalog} — see the note there for why a nullable term breaks.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND p.storeId = :storeId
              AND (:categoryId IS NULL OR p.categoryId = :categoryId)
              AND LOWER(p.name) LIKE :namePattern ESCAPE '\\'
            """)
    Page<Product> findActiveInStore(@Param("storeId") UUID storeId,
                                    @Param("categoryId") UUID categoryId,
                                    @Param("namePattern") String namePattern,
                                    Pageable pageable);

    /**
     * The aisles a store actually stocks, with a count each.
     *
     * <p>Driving the Aisles tab from the catalog rather than from the category tree means a store
     * never shows an empty aisle — the grocery taxonomy is platform-wide, but no single shop
     * carries all of it.
     */
    @Query("""
            SELECT p.categoryId, COUNT(p) FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND p.storeId = :storeId
              AND p.categoryId IS NOT NULL
            GROUP BY p.categoryId
            """)
    java.util.List<Object[]> countActiveByCategoryInStore(@Param("storeId") UUID storeId);

    java.util.List<Product> findByIdIn(java.util.Collection<UUID> ids);

    /**
     * A page of named products from one store.
     *
     * <p>Both predicates matter: the ids say which, the store says whose. Without the store filter
     * this would read any product in the catalog given its id.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND p.storeId = :storeId
              AND p.id IN :ids
            """)
    Page<Product> findActiveInStoreByIds(@Param("storeId") UUID storeId,
                                         @Param("ids") java.util.Collection<UUID> ids,
                                         Pageable pageable);
}
