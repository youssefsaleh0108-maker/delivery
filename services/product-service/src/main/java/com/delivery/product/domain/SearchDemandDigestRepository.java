package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** The ledger of weekly digests already raised. */
public interface SearchDemandDigestRepository extends JpaRepository<SearchDemandDigest, UUID> {

    boolean existsByWeekStartAndMerchantId(Instant weekStart, String merchantId);

    /** Ledger rows for weeks nobody would re-send anyway. */
    @Modifying
    @Query("DELETE FROM SearchDemandDigest d WHERE d.weekStart < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}
