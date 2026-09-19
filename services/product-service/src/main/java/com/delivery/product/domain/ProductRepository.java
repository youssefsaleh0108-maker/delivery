package com.delivery.product.domain;

import java.util.Collection;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProductRepository extends JpaRepository<Product, UUID> {

    /** The Merchant Portal's list — everything the merchant owns, any status. */
    Page<Product> findByMerchantId(String merchantId, Pageable pageable);

    /**
     * The merchant's list narrowed to one status.
     *
     * <p>How the provider dashboard counts its "Active offers": {@code GET /api/products/mine?status=
     * ACTIVE&size=1} and the page's {@code totalElements}, a count the database made rather than the
     * length of whatever page a client happened to load.
     */
    Page<Product> findByMerchantIdAndStatus(String merchantId, Product.Status status, Pageable pageable);

    /**
     * The merchant's list in one of their shops, in any status.
     *
     * <p>Scoped by merchant as well as by shop, although the caller has already checked the shop is the
     * merchant's: a row that disagreed about its owner is one this list must not show.
     */
    Page<Product> findByMerchantIdAndStoreId(String merchantId, UUID storeId, Pageable pageable);

    /**
     * One shop's products in one status: how the provider dashboard counts its service shop's "Active
     * offers" when the account owns a goods shop too
     * ({@code GET /api/products/mine?storeId=&status=ACTIVE&size=1}).
     */
    Page<Product> findByMerchantIdAndStoreIdAndStatus(String merchantId, UUID storeId,
                                                     Product.Status status, Pageable pageable);

    Optional<Product> findByIdAndMerchantId(UUID id, String merchantId);

    /**
     * One product, with its row locked until the transaction ends. This is how back office reads an offer
     * it is taking down or restoring ({@code OfferModerationService}).
     *
     * <p>Without the lock, two staff acting on one offer at once would both find it not taken down. Both
     * would write a TAKE_DOWN row, and the second reason would silently replace the first as the one its
     * provider reads. With the lock, the second waits and then finds the offer already taken down.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM Product p WHERE p.id = :id")
    Optional<Product> findForModerationById(@Param("id") UUID id);

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
     *
     * <p><strong>Never an offer of a service shop.</strong> A service offer is a product row, and this
     * list is every live product of every shop, so without the store filter a print shop's "500
     * business cards" would be listed among the groceries. Pinned in the query rather than left to
     * callers, for the reason {@link StoreRepository#findStorefront} gives about ACTIVE. Service offers
     * are found through their own read, which asks for them by name.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND (:categoryId IS NULL OR p.categoryId = :categoryId)
              AND LOWER(p.name) LIKE :namePattern ESCAPE '\\'
              AND p.storeId NOT IN (
                    SELECT s.id FROM Store s
                    WHERE s.vertical = com.delivery.product.domain.Store$Vertical.SERVICES)
            """)
    Page<Product> findActiveCatalog(@Param("categoryId") UUID categoryId,
                                    @Param("namePattern") String namePattern,
                                    Pageable pageable);

    long countByCategoryId(UUID categoryId);

    /**
     * The gift hub's featured bundles: live products the back office picked, newest pick first.
     *
     * <p>Only the product's own state is decided here. Whether its shop is listed, and whether the
     * stock projection says it can be sold, is decided in {@code GiftBundleService} against the
     * rows it reads, where it can be tested. Bounded by the caller's page.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.giftFeatured = true
              AND p.status = com.delivery.product.domain.Product$Status.ACTIVE
            ORDER BY p.giftFeaturedAt DESC, p.id ASC
            """)
    java.util.List<Product> findFeaturedGifts(Pageable pageable);

    /**
     * Products in a section that a customer could still be shown.
     *
     * <p>Products are archived, never deleted, so an unfiltered count keeps a section pinned open
     * for goods that left the shelf months ago and can never be un-counted.
     */
    long countByCategoryIdAndStatusNot(UUID categoryId, Product.Status status);

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
     * A store's shelf searched for a term: {@link #findActiveInStore}'s match, and also the item search's.
     *
     * <p>The customer item search ({@link ItemSearchRepository#findCandidateRows}) groups what it finds by
     * shop and says "5 more in this shop", which opens the shop searched for the same words. If the shelf
     * only matched {@code LOWER(name) LIKE}, a shop found for "احمد" through its "أحمد" product, or for
     * "nescafe" through "Nescafé", would open onto nothing. So a product is on this page when its lowered
     * name contains the term, as before, or when it reaches one of the item search's tiers on
     * {@code search_name} (V37): the folded term is in the folded name, every folded word of it is, or it
     * sounds like part of it. Best match first, in the item search's order, then by name.
     *
     * <p>Native, because {@code search_name} is unmapped and the tiers need pg_trgm; so it is used only
     * for a search, and the page's order is this query's own: the caller passes an unsorted page. Out of
     * stock is not filtered here, as the shelf never has.
     *
     * @param inAisle    whether {@code categoryId} narrows the shelf; when false it is ignored, and is
     *                   never null, since a null bound into native SQL has no type
     * @param namePattern {@link com.delivery.product.service.SearchPatterns#like} of the term
     */
    @Query(value = """
            SELECT p.*
              FROM products p
             CROSS JOIN (SELECT NULLIF(search_fold(CAST(:term AS text)), '') AS f) t
             WHERE p.status = 'ACTIVE'
               AND p.store_id = CAST(:storeId AS uuid)
               AND (NOT CAST(:inAisle AS boolean) OR p.category_id = CAST(:categoryId AS uuid))
               AND (LOWER(p.name) LIKE CAST(:namePattern AS text) ESCAPE '\\'
                    OR strpos(p.search_name, t.f) > 0
                    OR (t.f IS NOT NULL AND NOT EXISTS (
                            SELECT 1 FROM unnest(string_to_array(t.f, ' ')) AS w(word)
                             WHERE strpos(p.search_name, w.word) = 0))
                    OR t.f OPERATOR(public.<%) p.search_name)
             ORDER BY CASE
                        WHEN LOWER(p.name) LIKE CAST(:namePattern AS text) ESCAPE '\\'
                          OR strpos(p.search_name, t.f) > 0 THEN 1
                        WHEN t.f IS NOT NULL AND NOT EXISTS (
                               SELECT 1 FROM unnest(string_to_array(t.f, ' ')) AS w(word)
                                WHERE strpos(p.search_name, w.word) = 0) THEN 2
                        ELSE 3
                      END,
                      COALESCE(public.word_similarity(t.f, p.search_name), 0) DESC,
                      p.name, p.id
            """,
            countQuery = """
            SELECT count(*)
              FROM products p
             CROSS JOIN (SELECT NULLIF(search_fold(CAST(:term AS text)), '') AS f) t
             WHERE p.status = 'ACTIVE'
               AND p.store_id = CAST(:storeId AS uuid)
               AND (NOT CAST(:inAisle AS boolean) OR p.category_id = CAST(:categoryId AS uuid))
               AND (LOWER(p.name) LIKE CAST(:namePattern AS text) ESCAPE '\\'
                    OR strpos(p.search_name, t.f) > 0
                    OR (t.f IS NOT NULL AND NOT EXISTS (
                            SELECT 1 FROM unnest(string_to_array(t.f, ' ')) AS w(word)
                             WHERE strpos(p.search_name, w.word) = 0))
                    OR t.f OPERATOR(public.<%) p.search_name)
            """,
            nativeQuery = true)
    Page<Product> findActiveInStoreMatching(@Param("storeId") UUID storeId,
                                            @Param("inAisle") boolean inAisle,
                                            @Param("categoryId") UUID categoryId,
                                            @Param("term") String term,
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

    /**
     * The customer services search: live offers of listed service shops, in the given open categories.
     *
     * <p>Three filters, each for a reason:
     * <ul>
     *   <li>The offer is ACTIVE, so a paused offer, a draft or an archived product never reaches a
     *       customer. Nor does an offer back office took down, which is archived.
     *   <li>Its shop is ACTIVE, so a draft or suspended shop's offers are not listed, as its shelf is
     *       not.
     *   <li>Its shop is a SERVICES shop in one of {@code categories}: never a goods product, whatever
     *       its name says, and never an offer of a shop in a closed category. The category is the
     *       shop's (V33); an offer has none of its own.
     * </ul>
     *
     * <p>{@code categories} is never empty: {@code ServiceOfferSearch} answers an empty page itself
     * when no category may be shown, for the reason {@link StoreRepository#findServicesStorefront}
     * gives. The name pattern follows {@link #findActiveCatalog}'s non-null contract.
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status = com.delivery.product.domain.Product$Status.ACTIVE
              AND LOWER(p.name) LIKE :namePattern ESCAPE '\\'
              AND p.storeId IN (
                    SELECT s.id FROM Store s
                    WHERE s.status = com.delivery.product.domain.Store$Status.ACTIVE
                      AND s.vertical = com.delivery.product.domain.Store$Vertical.SERVICES
                      AND s.serviceCategory IN :categories)
            """)
    Page<Product> findListedServiceOffers(
            @Param("categories") java.util.Collection<Store.ServiceCategory> categories,
            @Param("namePattern") String namePattern,
            Pageable pageable);

    /**
     * Back office's list of service offers: every service shop's offers in every status, narrowed by what
     * the caller names ({@code OfferModerationService#list}).
     *
     * <p>This is not a customer read, and it deliberately leaves out what the customer reads filter on. A
     * draft or suspended shop's offers are here, and so is an offer in a closed category or one back
     * office took down: those are the offers back office has to be able to find. It is still never a
     * goods product, which the back office catalogue reads elsewhere.
     *
     * <p>Every argument is non-null except {@code storeId}, for the reason {@link #findActiveCatalog}
     * gives about nullable parameters:
     * <ul>
     *   <li>{@code statuses} and {@code categories} are never empty; unfiltered, they hold every value.
     *   <li>{@code takenDownOnly} and {@code takenDownExcluded} split ARCHIVED in two: taken down by back
     *       office, or archived by the provider. A hold implies ARCHIVED ({@code chk_product_takedown}),
     *       so no other status needs the split.
     *   <li>{@code storeId} is compared only to a typed column, as {@code categoryId} is above.
     *   <li>{@code namePattern} matches the offer's name or its shop's, since a complaint names either.
     * </ul>
     */
    @Query("""
            SELECT p FROM Product p
            WHERE p.status IN :statuses
              AND (:takenDownOnly = false OR p.takenDownAt IS NOT NULL)
              AND (:takenDownExcluded = false OR p.takenDownAt IS NULL)
              AND p.storeId IN (
                    SELECT s.id FROM Store s
                    WHERE s.vertical = com.delivery.product.domain.Store$Vertical.SERVICES
                      AND s.serviceCategory IN :categories
                      AND (:storeId IS NULL OR s.id = :storeId))
              AND (LOWER(p.name) LIKE :namePattern ESCAPE '\\'
                   OR p.storeId IN (
                        SELECT n.id FROM Store n
                        WHERE LOWER(n.name) LIKE :namePattern ESCAPE '\\'))
            """)
    Page<Product> findServiceOffersForBackoffice(
            @Param("statuses") Collection<Product.Status> statuses,
            @Param("takenDownOnly") boolean takenDownOnly,
            @Param("takenDownExcluded") boolean takenDownExcluded,
            @Param("categories") Collection<Store.ServiceCategory> categories,
            @Param("storeId") UUID storeId,
            @Param("namePattern") String namePattern,
            Pageable pageable);
}
