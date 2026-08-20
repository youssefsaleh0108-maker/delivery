package com.delivery.product.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreOfferRepository extends JpaRepository<StoreOffer, UUID> {

    List<StoreOffer> findByStoreIdAndActiveIsTrue(UUID storeId);

    /**
     * Everything currently on the Offers tab: this store's promotions plus the platform-wide ones.
     *
     * <p>{@code storeId IS NULL} is the platform-wide arm of the union, not a missing value. Live
     * window filtering is left to {@link StoreOffer#isLiveAt} rather than done here so the two
     * rules — "is it switched on" and "is it in its window" — stay in one place and are unit
     * testable without a database.
     */
    @Query("""
            SELECT o FROM StoreOffer o
            WHERE o.active = true
              AND (o.storeId = :storeId OR o.storeId IS NULL)
            ORDER BY o.storeId NULLS LAST, o.startsAt DESC
            """)
    List<StoreOffer> findLiveFor(@Param("storeId") UUID storeId);

    /** The home screen's Offers rail: platform-wide promotions and every store's live ones. */
    @Query("SELECT o FROM StoreOffer o WHERE o.active = true ORDER BY o.storeId NULLS FIRST, o.startsAt DESC")
    List<StoreOffer> findAllLive();
}
