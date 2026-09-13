package com.delivery.product.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CatalogScanRepository extends JpaRepository<CatalogScan, UUID> {

    /** The only way a scan is read for a merchant: by id AND owner, so a stranger's id is empty. */
    Optional<CatalogScan> findByIdAndMerchantId(UUID id, String merchantId);

    /**
     * The same owner-scoped read, holding the scan row's write lock for the transaction.
     *
     * <p>For every write that checks a state and then changes it. Without it, two "analyse" taps
     * arriving together both see UPLOADING and both queue a paid provider call; with it the second
     * sees ANALYZING and is refused.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM CatalogScan s WHERE s.id = :id AND s.merchantId = :merchantId")
    Optional<CatalogScan> lockOwned(@Param("id") UUID id, @Param("merchantId") String merchantId);

    /** The daily quota: scans this merchant started since {@code since}. */
    long countByMerchantIdAndCreatedAtAfter(String merchantId, Instant since);

    /**
     * The same scans as the quota counts, newest first: what "pick up where I left off" chooses
     * from. Bounded by that quota, so a handful of rows at most.
     */
    List<CatalogScan> findByMerchantIdAndCreatedAtAfterOrderByCreatedAtDesc(String merchantId,
                                                                           Instant since);

    /** The merchant lock's first key: its own name among every advisory lock in the database. */
    int MERCHANT_SCAN_LOCK = 29_001;

    /**
     * Serialises this merchant's scan starts and readings for the rest of the transaction.
     *
     * <p>Both checks it guards count across ALL of a merchant's scans — the daily quota, and one
     * reading at a time — and a merchant may own several stores. So the lock is the merchant's, not a
     * store's: this used to lock the store row, which let parallel starts in two of the merchant's
     * stores each see room for one more. There is no merchant row in this service to lock, so it is a
     * transaction-scoped advisory lock on the merchant's id, released at commit or rollback and
     * never leaked by a request that dies.
     *
     * <p>The two-key form, with a fixed first key naming this lock, so it cannot collide with any
     * other advisory lock in the database — Flyway's included, which uses the single-key form, a
     * separate key space. {@code hashtext} folds the id into the second key: two merchants who share
     * a hash only ever wait for each other, never get past each other. Selected FROM the function
     * because it returns void, which has no Java type to map to.
     */
    @Query(value = "SELECT 1 FROM pg_advisory_xact_lock(" + MERCHANT_SCAN_LOCK + ", hashtext(:merchantId))",
            nativeQuery = true)
    int lockMerchant(@Param("merchantId") String merchantId);

    /**
     * How many of this merchant's OTHER scans are being read by a job that may still be alive: one
     * started at or after {@code aliveSince}. A reading lost with its pod stops counting once it is
     * stale, as it does everywhere else.
     */
    @Query("SELECT COUNT(s) FROM CatalogScan s WHERE s.merchantId = :merchantId AND s.id <> :scanId "
            + "AND s.status = :status AND s.analysisStartedAt >= :aliveSince")
    long countOtherLiveAnalyses(@Param("merchantId") String merchantId, @Param("scanId") UUID scanId,
                                @Param("status") CatalogScan.Status status,
                                @Param("aliveSince") Instant aliveSince);
}
