package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.delivery.accounting.domain.RiderLedgerEntry.EntryType;

/**
 * One rider's money movements.
 *
 * <p>A top-level interface for the same reason {@link PointsEntryRepository} is one: Spring Data
 * finds repositories by classpath scanning and skips an interface nested inside another type, which
 * fails at startup as a missing bean rather than as a nesting problem.
 */
public interface RiderLedgerRepository extends JpaRepository<RiderLedgerEntry, UUID> {

    /**
     * What the platform owes this rider right now.
     *
     * <p>{@code PLATFORM} only, and that filter is the whole rule. A carrier's rider has
     * {@code JOB_EARNING} rows the platform must never pay — it already paid their company — and a
     * cash tip is money the rider is holding. Both are earnings and neither is a balance; summing
     * every row instead would offer to pay for the same delivery twice.
     *
     * <p>{@code COALESCE} so a rider who has never worked reads 0 rather than null. Every caller
     * would otherwise need the same null check and one of them would forget.
     */
    @Query("""
            SELECT COALESCE(SUM(e.amount), 0) FROM RiderLedgerEntry e
             WHERE e.riderRef = :rider
               AND e.payableBy = com.delivery.accounting.domain.RiderLedgerEntry$PayableBy.PLATFORM
            """)
    BigDecimal balanceOf(@Param("rider") String rider);

    /**
     * Every row for one rider in a window, oldest first.
     *
     * <p>Bucketed by {@code earnedAt} rather than {@code createdAt}: a late redelivery must land in
     * the day the rider actually worked, or their Monday total changes on Tuesday.
     *
     * <p>Returns the ROWS and lets the caller total them, rather than grouping by day in SQL. The
     * grouping is a local-calendar question — which day a delivery at 23:40 UTC belongs to depends
     * on the rider's timezone — and expressing that in a native {@code date_trunc(... AT TIME ZONE
     * ...)} would put the rule in two places, one of which is untestable without a database. One
     * rider's window is at most a few hundred rows, so there is nothing to win by pushing it down.
     */
    @Query("""
            SELECT e FROM RiderLedgerEntry e
             WHERE e.riderRef = :rider
               AND e.earnedAt >= :from AND e.earnedAt < :to
             ORDER BY e.earnedAt ASC
            """)
    List<RiderLedgerEntry> between(@Param("rider") String rider,
                                   @Param("from") Instant from,
                                   @Param("to") Instant to);

    /** The rider's recent activity, newest first — what the Earnings screen lists. */
    List<RiderLedgerEntry> findByRiderRefOrderByEarnedAtDesc(String riderRef, Pageable pageable);

    /** The recent jobs, tips excluded, newest first. */
    List<RiderLedgerEntry> findByRiderRefAndEntryTypeOrderByEarnedAtDesc(
            String riderRef, EntryType entryType, Pageable pageable);

    /**
     * Every row this rider has against a set of orders.
     *
     * <p>Takes the whole set rather than one order at a time so the recent-jobs list, which has to
     * pair each job with its tip, costs two queries instead of one per job on screen.
     */
    List<RiderLedgerEntry> findByRiderRefAndOrderIdIn(String riderRef,
                                                      java.util.Collection<UUID> orderIds);

    /**
     * The job a tip is being added to.
     *
     * <p>How the tip endpoint learns who to pay without trusting the caller to name a rider. The
     * job earning was written when the order was delivered, so its existence is also the proof that
     * the order was in fact delivered and by whom.
     */
    java.util.Optional<RiderLedgerEntry> findFirstByOrderIdAndEntryType(
            UUID orderId, EntryType entryType);

    /**
     * The dedupe guard.
     *
     * <p>The unique index on (order_id, rider_ref, entry_type) is the real enforcement; this exists
     * so an ordinary at-least-once redelivery is a quiet no-op rather than a constraint violation
     * and a stack trace in a listener.
     */
    boolean existsByOrderIdAndRiderRefAndEntryType(UUID orderId, String riderRef,
                                                   EntryType entryType);
}
