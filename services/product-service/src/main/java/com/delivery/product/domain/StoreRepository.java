package com.delivery.product.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreRepository extends JpaRepository<Store, UUID> {

    Optional<Store> findBySlug(String slug);

    Optional<Store> findByIdAndMerchantId(UUID id, String merchantId);

    List<Store> findByMerchantIdOrderByCreatedAtDesc(String merchantId);

    Page<Store> findByMerchantIdOrderByCreatedAtDesc(String merchantId, Pageable pageable);

    boolean existsByMerchantId(String merchantId);

    /**
     * The storefront query.
     *
     * <p>Every filter is optional and expressed as "the parameter is null, or it matches". One query
     * and one plan, rather than a Specification tree. It is also why {@code search} arrives as an
     * already-built LIKE pattern rather than a raw term: a null pattern would make the comparison
     * null rather than true, and silently return nothing.
     *
     * <p>Prefer {@link #findStorefront} — the status is a parameter here only because a nested enum
     * constant is awkward to write as a JPQL literal, not because callers should choose it.
     */
    @Query("""
            SELECT s FROM Store s
            WHERE s.status = :status
              AND (:vertical IS NULL OR s.vertical = :vertical)
              AND (LOWER(s.name) LIKE :search)
              AND (:maxDeliveryFee IS NULL OR s.deliveryFee <= :maxDeliveryFee)
              AND (:maxEtaMinutes IS NULL OR s.etaMaxMinutes <= :maxEtaMinutes)
              AND (:minRating IS NULL OR s.rating >= :minRating)
            """)
    Page<Store> findStorefrontWithStatus(@Param("status") Store.Status status,
                                         @Param("vertical") Store.Vertical vertical,
                                         @Param("search") String search,
                                         @Param("maxDeliveryFee") BigDecimal maxDeliveryFee,
                                         @Param("maxEtaMinutes") Integer maxEtaMinutes,
                                         @Param("minRating") BigDecimal minRating,
                                         Pageable pageable);

    /**
     * Live stores only. The ACTIVE filter is pinned here rather than left to callers: a DRAFT or
     * SUSPENDED store reaching a customer's screen is the one failure this query must not allow,
     * and an invariant that every call site has to remember is not an invariant.
     */
    default Page<Store> findStorefront(Store.Vertical vertical, String search,
                                       BigDecimal maxDeliveryFee, Integer maxEtaMinutes,
                                       BigDecimal minRating, Pageable pageable) {
        return findStorefrontWithStatus(Store.Status.ACTIVE, vertical, search,
                maxDeliveryFee, maxEtaMinutes, minRating, pageable);
    }

    @Query("""
            SELECT s FROM Store s
            JOIN StoreFavorite f ON f.id.storeId = s.id
            WHERE f.id.userId = :userId
              AND s.status = :status
            ORDER BY f.createdAt DESC
            """)
    Page<Store> findFavoritesOfWithStatus(@Param("userId") String userId,
                                          @Param("status") Store.Status status,
                                          Pageable pageable);

    /** A customer's starred stores, most recently starred first. The home screen's top row. */
    default Page<Store> findFavoritesOf(String userId, Pageable pageable) {
        return findFavoritesOfWithStatus(userId, Store.Status.ACTIVE, pageable);
    }
}
