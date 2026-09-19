package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import jakarta.persistence.LockModeType;

public interface CashFloatRepository extends JpaRepository<CashFloatEntry, UUID> {

    /** The idempotency guard: the bus delivers at least once, and a debt must not be booked twice. */
    boolean existsByOrderIdAndEntryKind(UUID orderId, CashFloatEntry.Kind entryKind);

    /**
     * What one holder owes the PLATFORM, oldest first, so a remittance clears the longest-held cash
     * before the newest — and LOCKED.
     *
     * <p>The lock is the fix for a race that cost money. Two operators pressing "Banked" at once both
     * read the same outstanding rows, and both wrote a remittance and a CASH_REMITTANCE posting: the
     * platform would ask the bank for the same takings twice. With the rows locked the second call
     * waits for the first to commit, re-reads them as already cleared, and records nothing. Only the
     * write path may call this — Postgres refuses {@code FOR UPDATE} in a read-only transaction, which
     * is why the views read {@link #heldBy} instead.
     *
     * <p><strong>Never a rider's cash for a delivery company (RECON-03).</strong> A company's rider
     * owes the notes from its jobs to the company, which takes them in at its hub
     * ({@link #lockHeldForCarrier}) and then owes the platform. They are not the platform's to
     * record as banked: when they were, the Back Office's "banked" on a rider cleared 76.39 the
     * rider still owed company 5857ac51, and the company could never record its own hand-over. So a
     * rider's rows that name a company are left out here, and only there can they be cleared. A
     * company's own custody and a shop's till are owed to the platform directly and are always in.
     *
     * <p><strong>Every kind of cash the subject holds.</strong> One Keycloak subject can be a shop
     * and a rider at once — a shop that also delivers — and its till and its bag are owed on
     * different terms, so a remittance that was not told which of the two is paying refuses rather
     * than clear both as one. {@link #outstandingFor(String, CashFloatEntry.HolderKind)} is the one
     * that has been told.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
              AND (f.holderKind <> com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
                   OR f.carrierRef IS NULL)
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> outstandingFor(@Param("holder") String holder);

    /**
     * {@link #outstandingFor(String)} for one kind of holder, LOCKED: what a remittance clears once
     * it knows who is paying — a shop's till without the bag the same account carries as a rider,
     * or the reverse. The same rule applies: a rider's cash for a delivery company is never here.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.holderKind = :holderKind
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
              AND (f.holderKind <> com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
                   OR f.carrierRef IS NULL)
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> outstandingFor(@Param("holder") String holder,
                                        @Param("holderKind") CashFloatEntry.HolderKind holderKind);

    /** The same rows as {@link #outstandingFor}, unlocked, for pages that only read them. */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> heldBy(@Param("holder") String holder);

    /** {@link #outstandingFor(String, CashFloatEntry.HolderKind)}, unlocked: a shop's statement. */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.holderKind = :holderKind
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> heldBy(@Param("holder") String holder,
                                @Param("holderKind") CashFloatEntry.HolderKind holderKind);

    /**
     * Everything one kind of holder still holds, whoever holds it, oldest first: every shop's till
     * at once, so the Back Office's list can say what each shop owes out of it in one read.
     */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderKind = :holderKind
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> heldByKind(@Param("holderKind") CashFloatEntry.HolderKind holderKind);

    /**
     * What one holder still owes, as one kind of holder.
     *
     * <p>COALESCE, because a holder with nothing outstanding must read as zero rather than null —
     * "no rows" and "owes nothing" are the same answer here, and a null would propagate into every
     * report that adds these up.
     *
     * <p><strong>The kind is not optional.</strong> A shop that also delivers is one Keycloak subject
     * with a till and a rider's bag, and each is owed on its own terms: a rider's cash-out nets their
     * bag and never the shop's till, and a shop's statement counts its till and never the bag.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :holder
              AND f.holderKind = :holderKind
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            """)
    BigDecimal outstandingTotalFor(@Param("holder") String holder,
                                   @Param("holderKind") CashFloatEntry.HolderKind holderKind);

    /**
     * What a rider owes the PLATFORM right now: their outstanding cash, less any they hold for a
     * delivery company (RECON-12).
     *
     * <p>Cash from a company's jobs is owed to the company, which nets it in its own pay run
     * ({@code PayslipCalculator}) or takes it at its hub, and then answers to the platform for it.
     * Netting it against what the platform owes the rider as well took the same notes twice: a
     * rider owed 20.00 for own-fleet work and holding 30.00 for their company was told they could
     * take out -10.00. Never a shop's till either, which a shop that also delivers settles on its
     * own terms.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :rider
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
              AND f.carrierRef IS NULL
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            """)
    BigDecimal riderOwesPlatform(@Param("rider") String rider);

    /**
     * What the collections one remittance or transfer cleared came to. With the rows it wrote, this
     * is what a replayed shop's payment says it kept.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.clearedBy = :id
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
            """)
    BigDecimal clearedTotal(@Param("id") UUID id);

    /**
     * What one holder collected, or banked, inside a window, as one kind of holder (see
     * {@link #outstandingTotalFor} for why the kind is not optional).
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
              AND f.holderKind = :holderKind
              AND f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal totalForHolderBetween(@Param("holder") String holder,
                                     @Param("holderKind") CashFloatEntry.HolderKind holderKind,
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
              AND f.holderKind = :holderKind
              AND f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            ORDER BY f.createdAt
            """)
    List<CashFloatEntry> forHolderBetween(@Param("holder") String holder,
                                          @Param("holderKind") CashFloatEntry.HolderKind holderKind,
                                          @Param("kind") CashFloatEntry.Kind kind,
                                          @Param("from") Instant from,
                                          @Param("to") Instant to);

    /**
     * The same figure across every holder, for the platform's own statement.
     *
     * <p>Door cash only: a delivery company's custody copies are excluded. They are the same orders
     * a rider already collected, re-held after a hand-over, and counting them here would report
     * every carrier order's cash as collected twice. Remittances carry no hand-over, so the
     * "banked" figure is unaffected.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.entryKind = :kind
              AND f.handoverId IS NULL
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
     *
     * <p>Correct across a hand-over without a special case: the rider's rows are cleared by the
     * transfer and the company's copies are not, so the same cash is counted exactly once.
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

    /**
     * Everyone holding cash, one line per party it is owed to, largest first — the Back Office's
     * cash-on-hand list (RECON-03).
     *
     * <p>A rider can carry the platform's cash and a delivery company's at once, and the two are
     * different debts: the platform's is banked with the platform, and the company's is handed over
     * at the company's hub. {@link #outstandingByHolder()} adds them into one line, and the one
     * "banked" button on that line was how a rider's company cash came to be cleared as the
     * platform's. Grouped by the company as well, each debt is its own line with its own age, and
     * only the platform's line is one the Back Office can record as banked.
     *
     * <p>{@code carrierRef} is the company a rider's cash is owed to, and null for the platform's own
     * fleet. A company's custody always names itself there and a shop's till never names anybody, so
     * neither splits.
     */
    @Query("""
            SELECT f.holderRef AS holderRef,
                   f.holderKind AS holderKind,
                   f.carrierRef AS carrierRef,
                   SUM(f.amount) AS amount,
                   COUNT(f) AS orders,
                   MIN(f.createdAt) AS oldest
            FROM CashFloatEntry f
            WHERE f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            GROUP BY f.holderRef, f.holderKind, f.carrierRef
            ORDER BY SUM(f.amount) DESC
            """)
    List<CreditorBalance> outstandingByCreditor();

    /** A row of {@link #outstandingByCreditor()}. */
    interface CreditorBalance {
        String getHolderRef();

        CashFloatEntry.HolderKind getHolderKind();

        /** The company a rider's cash is owed to; null when it is owed to the platform. */
        String getCarrierRef();

        BigDecimal getAmount();

        long getOrders();

        java.time.Instant getOldest();
    }

    // --------------------------------------------------------------- delivery-company custody

    /**
     * What a rider handed to their delivery company inside a window — the credit that balances their
     * statement once the cash they collected has left their pocket for the company's hub.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :rider
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.TRANSFERRED
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal handedOverBetween(@Param("rider") String rider,
                                 @Param("from") Instant from,
                                 @Param("to") Instant to);

    /**
     * What a delivery company took into custody from its riders inside a window: its custody copies,
     * by when the hand-over happened.
     */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.PROVIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.handoverId IS NOT NULL
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal custodyReceivedBetween(@Param("carrier") String carrier,
                                      @Param("from") Instant from,
                                      @Param("to") Instant to);

    /** What a delivery company paid the platform inside a window. */
    @Query("""
            SELECT COALESCE(SUM(f.amount), 0) FROM CashFloatEntry f
            WHERE f.holderRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.PROVIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.REMITTED
              AND f.createdAt >= :from AND f.createdAt < :to
            """)
    BigDecimal carrierPaidBetween(@Param("carrier") String carrier,
                                  @Param("from") Instant from,
                                  @Param("to") Instant to);

    /**
     * What one rider still holds for one company, oldest first, LOCKED — the rows a hand-over
     * clears.
     *
     * <p>Only that company's rows. Cash the same rider took on the platform's own fleet, or for a
     * company they rode for before, is somebody else's to collect and stays exactly where it is.
     * Locked for the reason {@link #outstandingFor} is: two presses of "Confirm" must not both clear
     * the same notes.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :rider
              AND f.carrierRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> lockHeldForCarrier(@Param("rider") String rider,
                                            @Param("carrier") String carrier);

    /** {@link #lockHeldForCarrier}, unlocked, for the rider's settlement page. */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.holderRef = :rider
              AND f.carrierRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> heldForCarrier(@Param("rider") String rider,
                                        @Param("carrier") String carrier);

    /**
     * Every outstanding collection this company's riders are carrying for it.
     *
     * <p>Rows rather than a grouped total, and totalled in Java: the reconciliation page needs the
     * sum, the count, the oldest AND how much of it is past the overdue line, and one company's
     * unhanded cash is a few dozen rows at most. Grouping it four ways in SQL would put the overdue
     * rule in a second place.
     */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.carrierRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> heldByRidersFor(@Param("carrier") String carrier);

    /**
     * One company's rows of one kind in a window: its riders' collections, or its hand-overs.
     *
     * <p>{@code holderKind} is a parameter so the company's own custody copies can never be read as
     * its riders' door cash.
     */
    @Query("""
            SELECT f FROM CashFloatEntry f
            WHERE f.carrierRef = :carrier
              AND f.holderKind = :holderKind
              AND f.entryKind = :kind
              AND f.createdAt >= :from AND f.createdAt < :to
            ORDER BY f.createdAt ASC
            """)
    List<CashFloatEntry> forCarrierBetween(@Param("carrier") String carrier,
                                           @Param("holderKind") CashFloatEntry.HolderKind holderKind,
                                           @Param("kind") CashFloatEntry.Kind kind,
                                           @Param("from") Instant from,
                                           @Param("to") Instant to);

    /**
     * Every rider who has ever carried cash for this company.
     *
     * <p>Read from the float rather than from Order Manager's roster, deliberately: what a company is
     * answerable for is the cash its jobs produced, and a rider who left last week with notes still
     * in their pocket must still be on the page that chases them.
     */
    @Query("""
            SELECT DISTINCT f.holderRef FROM CashFloatEntry f
            WHERE f.carrierRef = :carrier
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
            """)
    List<String> ridersCarryingFor(@Param("carrier") String carrier);

    /** Whether this rider has ever carried cash for this company — the page's 404 test. */
    boolean existsByCarrierRefAndHolderRefAndHolderKind(String carrierRef, String holderRef,
                                                        CashFloatEntry.HolderKind holderKind);

    /** When each of this company's riders last handed cash over. [holderRef, Instant]. */
    @Query("""
            SELECT f.holderRef, MAX(f.createdAt) FROM CashFloatEntry f
            WHERE f.carrierRef = :carrier
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.TRANSFERRED
            GROUP BY f.holderRef
            """)
    List<Object[]> lastHandoverByRider(@Param("carrier") String carrier);

    /** A company's hand-overs, newest first. */
    List<CashFloatEntry> findByCarrierRefAndEntryKindOrderByCreatedAtDesc(
            String carrierRef, CashFloatEntry.Kind entryKind, Pageable pageable);

    /** One rider's hand-overs to one company, newest first. */
    List<CashFloatEntry> findByCarrierRefAndHolderRefAndEntryKindOrderByCreatedAtDesc(
            String carrierRef, String holderRef, CashFloatEntry.Kind entryKind, Pageable pageable);

    /** What a holder has banked with the platform, newest first — a company's payments. */
    List<CashFloatEntry> findByHolderRefAndHolderKindAndEntryKindOrderByCreatedAtDesc(
            String holderRef, CashFloatEntry.HolderKind holderKind, CashFloatEntry.Kind entryKind,
            Pageable pageable);

    /** The row a client's idempotency key already produced, if any. */
    Optional<CashFloatEntry> findByRequestKey(String requestKey);

    /** How many collections each of these hand-overs or remittances cleared. [id, count]. */
    @Query("""
            SELECT f.clearedBy, COUNT(f) FROM CashFloatEntry f
            WHERE f.clearedBy IN :ids
            GROUP BY f.clearedBy
            """)
    List<Object[]> countClearedBy(@Param("ids") Collection<UUID> ids);

    /**
     * Cash still in the pockets of each company's riders, for the Back Office.
     * [carrierRef, amount, riders, oldest].
     */
    @Query("""
            SELECT f.carrierRef, SUM(f.amount), COUNT(DISTINCT f.holderRef), MIN(f.createdAt)
            FROM CashFloatEntry f
            WHERE f.carrierRef IS NOT NULL
              AND f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.RIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.COLLECTED
              AND f.clearedBy IS NULL
            GROUP BY f.carrierRef
            """)
    List<Object[]> withRidersByCarrier();

    /** When each company last paid the platform. [holderRef, Instant]. */
    @Query("""
            SELECT f.holderRef, MAX(f.createdAt) FROM CashFloatEntry f
            WHERE f.holderKind = com.delivery.accounting.domain.CashFloatEntry$HolderKind.PROVIDER
              AND f.entryKind = com.delivery.accounting.domain.CashFloatEntry$Kind.REMITTED
            GROUP BY f.holderRef
            """)
    List<Object[]> lastRemittedByCarrier();
}
