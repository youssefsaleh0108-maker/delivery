package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CashFloatRepository extends JpaRepository<CashFloatEntry, UUID> {

    /** The idempotency guard: the bus delivers at least once, and a debt must not be booked twice. */
    boolean existsByOrderIdAndEntryKind(UUID orderId, CashFloatEntry.Kind entryKind);

    /** Oldest first, so a remittance clears the longest-held cash before the newest. */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> outstandingFor(@Param("holder") String holder);

    /**
     * What one person still owes.
     *
     * <p>COALESCE, because a holder with nothing outstanding must read as zero rather than null —
     * "no rows" and "owes nothing" are the same answer here, and a null would propagate into every
     * report that adds these up.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            """)
    BigDecimal outstandingTotalFor(@Param("holder") String holder);

    /** Everyone currently holding platform cash, largest first — the operator's collection list. */
    @Query("""
            SELECT f.holderRef AS holderRef,
                   f.holderKind AS holderKind,
                   SUM(f.amount) AS amount,
                   COUNT(f) AS orders,
                   MIN(f.createdAt) AS oldest
            FROM CashFloatEntry f
            WHERE f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            GROUP BY f.holderRef, f.holderKind
            ORDER BY SUM(f.amount) DESC
            """)
    List<HolderBalance> outstandingByHolder();

    /** A row of {@link #outstandingByHolder()}. */
    interface HolderBalance {
        String getHolderRef();

        CashFloatEntry.HolderKind getHolderKind();

        BigDecimal getAmount();

        long getOrders();

        java.time.Instant getOldest();
    }
}
