package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
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

    /**
     * What one holder collected, or banked, inside a window.
     *
     * <p>The two halves of the rider's cash line, and they are asked for separately rather than
     * netted in SQL because a statement has to SHOW both. "You took 2,425 and banked 2,100" is a
     * sentence a rider can check against their own week; "you owe 325" is one they can only argue
     * with.
     *
     * <p>Half-open, matching the ledger queries: {@code to} is the exclusive start of the day after
     * the range ends.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal totalForHolderBetween(@Param("holder") String holder,
                                     @Param("kind") CashFloatEntry.Kind kind,
                                     @Param("from") java.time.Instant from,
                                     @Param("to") java.time.Instant to);

    /**
     * The rows behind that total, so a statement can itemise them.
     *
     * <p>Needed because a rider's itemisation used to come only from {@code rider_ledger}, and on a
     * platform where the delivery fee is zero that table is empty — so a rider was shown a single
     * line saying they owed the platform two thousand four hundred dollars with nothing underneath
     * it. The cash they took was collected against specific orders and every one of them is a row
     * here; a figure somebody is asked to hand back has to be checkable against the jobs that
     * produced it.
     */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            ORDER BY f.createdAt
            """)
    List<CashFloatEntry> forHolderBetween(@Param("holder") String holder,
                                          @Param("kind") CashFloatEntry.Kind kind,
                                          @Param("from") Instant from,
                                          @Param("to") Instant to);

    /** The same figure across every holder, for the platform's own statement. */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal totalBetween(@Param("kind") CashFloatEntry.Kind kind,
                            @Param("from") java.time.Instant from,
                            @Param("to") java.time.Instant to);

    /**
     * Everything anybody is still holding, right now, whenever they collected it.
     *
     * <p>Deliberately NOT range-scoped, and used only in a statement's {@code note}. Cash collected
     * in July and still not banked in August is a fact about today that no August window can show,
     * and leaving it out of the note is how a statement can be arithmetically perfect and still
     * mislead the person reading it.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            """)
    BigDecimal outstandingTotal();

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
