package com.delivery.product.domain;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreReviewRepository extends JpaRepository<StoreReview, UUID> {

    Page<StoreReview> findByStoreIdOrderByCreatedAtDesc(UUID storeId, Pageable pageable);

    Optional<StoreReview> findByOrderId(UUID orderId);

    /**
     * The aggregate, recomputed from the reviews themselves.
     *
     * <p>Recomputed rather than incremented: an incremental average drifts the moment a review is
     * edited or deleted, and there is no way to notice. This runs once per review write, not per
     * read — the storefront reads the denormalised column on {@code stores}.
     */
    @Query("""
            SELECT new com.delivery.product.domain.StoreReviewRepository$RatingAggregate(
                       AVG(r.rating), COUNT(r))
            FROM StoreReview r WHERE r.storeId = :storeId
            """)
    RatingAggregate aggregateFor(@Param("storeId") UUID storeId);

    /**
     * A constructor expression rather than {@code Object[]}: the array form's shape varies with
     * the number of selections and quietly returns a nested array in some Hibernate versions.
     *
     * <p>{@code average} is null when a store has no reviews at all — which must stay distinct from
     * a genuine zero, so the card can say "New" rather than implying a bad score.
     */
    record RatingAggregate(Double average, Long count) {
    }
}
