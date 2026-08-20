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
