package com.delivery.accounting.domain;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AccountingTransactionRepository extends JpaRepository<AccountingTransaction, UUID> {

    List<AccountingTransaction> findByOrderIdOrderByCreatedAt(UUID orderId);

    /**
     * The dedupe guard.
     *
     * <p>The unique constraint on (order_id, leg) is the real enforcement; this check exists so the
     * ordinary at-least-once redelivery is a quiet no-op rather than a constraint violation and a
     * stack trace in a listener.
     */
    boolean existsByOrderId(UUID orderId);

    // ------------------------------------------------------------------------------ statements

    /**
     * One party's own legs over a window.
     *
     * <p>Bucketed on {@code createdAt}, which on this table is the moment the settlement was
     * written. There is no delivered-at column here — {@code rider_ledger.earned_at} exists for
     * precisely that reason and only riders needed it — so a statement range is a range over when
     * the money was recorded. Worth stating because it differs from the rider's Earnings screen by
     * however long the bus took.
     *
     * <p>Half-open on purpose: {@code to} is the exclusive start of the day after the inclusive end
     * date, so no leg written at 23:59:59.999 falls out of the month it belongs to.
     */
    @Query("""
            select t from AccountingTransaction t
             where t.counterpartyKind = :kind
               and t.counterpartyRef = :ref
               and t.createdAt >= :from and t.createdAt < :to
             order by t.createdAt
            """)
    List<AccountingTransaction> legsForCounterparty(
            @Param("kind") CounterpartyKind kind,
            @Param("ref") String ref,
            @Param("from") Instant from,
            @Param("to") Instant to);

    /**
     * Every leg of a set of orders.
     *
     * <p>A statement needs its counterparty's own legs AND the rest of each order's legs: what the
     * platform took on an order is on the platform's leg, not on the merchant's, and a merchant
     * statement that showed only what it could see would have no commission line at all. Fetched for
     * the whole order set at once rather than per order, so a month is two queries and not two
     * hundred.
     */
    List<AccountingTransaction> findByOrderIdIn(Collection<UUID> orderIds);

    /**
     * Everyone with activity in a window.
     *
     * <p>Returns the identities only; the figures are built per party afterwards. Doing the
     * arithmetic in SQL would mean a second implementation of every rule in
     * {@code StatementService}, and the two would disagree the first time one of them was changed.
     */
    @Query("""
            select distinct t.counterpartyKind, t.counterpartyRef from AccountingTransaction t
             where t.counterpartyKind is not null
               and t.createdAt >= :from and t.createdAt < :to
            """)
    List<Object[]> activeCounterparties(@Param("from") Instant from, @Param("to") Instant to);

    /**
     * Money paid out in the window that cannot be assigned to anybody.
     *
     * <p>Every row written before V47, and any later row whose event named no party. This is the
     * number the {@code unattributed} block reports, and it is the honest counterweight to a
     * counterparties listing that would otherwise look complete while omitting most of the money.
     *
     * <p>PAYEE legs only. A {@code CUSTOMER_DEBIT} has no counterparty by design and would sit in
     * this total forever, turning a figure that should fall to zero into one that never can.
     */
    @Query("""
            select coalesce(sum(t.amount), 0), count(distinct t.orderId)
              from AccountingTransaction t
             where t.counterpartyKind is null
               and t.leg in :legs
               and t.createdAt >= :from and t.createdAt < :to
            """)
    List<Object[]> unattributedTotal(@Param("legs") Collection<AccountingTransaction.Leg> legs,
                                     @Param("from") Instant from,
                                     @Param("to") Instant to);

    /** The legs that pay somebody. What "unattributed money" means. */
    Set<AccountingTransaction.Leg> PAYEE_LEGS = Set.of(
            AccountingTransaction.Leg.MERCHANT_CREDIT,
            AccountingTransaction.Leg.RIDER_CREDIT,
            AccountingTransaction.Leg.PROVIDER_CREDIT);

    /** The reconciliation view: what has not reached a terminal state. */
    @Query("select t from AccountingTransaction t where t.status in "
            + "(com.delivery.accounting.domain.AccountingTransaction$Status.PENDING, "
            + " com.delivery.accounting.domain.AccountingTransaction$Status.FAILED) "
            + "order by t.createdAt")
    List<AccountingTransaction> findUnsettled(Pageable pageable);

    List<AccountingTransaction> findByStatusOrderByCreatedAtDesc(
            AccountingTransaction.Status status, Pageable pageable);

    @Query("select t.status, count(t), coalesce(sum(t.amount), 0) from AccountingTransaction t "
            + "group by t.status")
    List<Object[]> summariseByStatus();

    /**
     * Legs the saga is still waiting on, older than a given moment.
     *
     * <p>A leg sitting {@code PENDING} is not an error state — it is the normal shape of an
     * in-flight settlement, which is exactly why it needs a clock against it. Nothing ever logs
     * "still waiting", so without this the difference between a bank taking four seconds and a
     * result message that was never delivered is invisible.
     *
     * <p>Derived rather than written out, so there is no query string to get wrong.
     */
    long countByStatusAndCreatedAtBefore(AccountingTransaction.Status status, Instant before);

    /**
     * Orders where the customer's money left and nothing has reached anybody else.
     *
     * <p>The acute case, and the one the bank connector's own notes call the worst state this
     * system can reach. It is silent by construction: the debit succeeded, so nothing failed; the
     * saga is waiting, so nothing errored. The only way to see it is to go looking.
     *
     * <p>Prefer {@link #countDebitedWithoutCounterpartOlderThan(Instant)}, which supplies the leg
     * and status sets — they are part of what the question <em>means</em>, not a caller's choice.
     */
    @Query("""
            select count(distinct debit.orderId) from AccountingTransaction debit
            where debit.leg = :debitLeg
              and debit.status = :postedStatus
              and debit.postedAt < :before
              and not exists (
                  select 1 from AccountingTransaction credit
                  where credit.orderId = debit.orderId
                    and credit.leg in :counterpartLegs
                    and credit.status in :dischargedStatuses
              )
            """)
    long countDebitedWithoutCounterpart(
            @Param("before") Instant before,
            @Param("debitLeg") AccountingTransaction.Leg debitLeg,
            @Param("postedStatus") AccountingTransaction.Status postedStatus,
            @Param("counterpartLegs") Collection<AccountingTransaction.Leg> counterpartLegs,
            @Param("dischargedStatuses") Collection<AccountingTransaction.Status> dischargedStatuses);

    /**
     * The legs that discharge a customer debit — somebody was paid, or the customer got it back.
     *
     * <p>{@code CUSTOMER_REFUND} counts: an order that was unwound is resolved, not stuck. The cash
     * legs are absent because a cash order never produces a {@code CUSTOMER_DEBIT} to begin with.
     */
    Set<AccountingTransaction.Leg> COUNTERPART_LEGS = Set.of(
            AccountingTransaction.Leg.MERCHANT_CREDIT,
            AccountingTransaction.Leg.RIDER_CREDIT,
            AccountingTransaction.Leg.PROVIDER_CREDIT,
            AccountingTransaction.Leg.CUSTOMER_REFUND);

    /** States in which a counterpart leg has genuinely discharged — the money reached someone. */
    Set<AccountingTransaction.Status> DISCHARGED_STATUSES = Set.of(
            AccountingTransaction.Status.POSTED,
            AccountingTransaction.Status.SETTLED_IN_CASH);

    /**
     * Orders debited without a counterpart, with the sets that define the question supplied.
     *
     * <p>Compensated debits are excluded by requiring {@code POSTED} on the debit: a reversal moves
     * it out of that state, which is the saga working rather than a settlement stuck.
     */
    default long countDebitedWithoutCounterpartOlderThan(Instant before) {
        return countDebitedWithoutCounterpart(before,
                AccountingTransaction.Leg.CUSTOMER_DEBIT,
                AccountingTransaction.Status.POSTED,
                COUNTERPART_LEGS,
                DISCHARGED_STATUSES);
    }
}
