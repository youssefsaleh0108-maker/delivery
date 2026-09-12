package com.delivery.product.domain;

import java.time.Instant;
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
     * Takes the store row's write lock for the rest of the transaction.
     *
     * <p>The quota is a count-then-insert, and two requests racing through it would both see room
     * for one more. Serialising scan creation on the store row closes that — a burst of parallel
     * "start scan" calls queues here instead of each spending a paid analysis. A plain
     * {@code SELECT ... FOR UPDATE}, chosen over an advisory lock because it is portable JPQL the
     * query-parse test can hold down, and because the row it locks is the one the scan hangs off.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM Store s WHERE s.id = :storeId")
    Optional<Store> lockStore(@Param("storeId") UUID storeId);
}
