package com.delivery.accounting.service;

import java.time.Duration;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.AccountingTransactionRepository;

/**
 * Answers "is any money stuck?" — the question nothing else in this service asks.
 *
 * <p>Every other failure here announces itself. A refused posting produces a {@code FAILED} leg and
 * a log line; a bank that will not answer trips a circuit breaker. The state this exists for makes
 * no noise at all: the customer's debit <em>succeeded</em>, so nothing failed, and the saga is
 * waiting for a result that is never coming — a dropped result message, a connector that died
 * between posting and reporting, a queue somebody purged. From inside the saga that is
 * indistinguishable from a bank taking its time.
 *
 * <p>So the only way to see it is a clock. Both figures below are counts of things that have been
 * true for <em>too long</em>, which is why the thresholds are configuration rather than constants:
 * what counts as too long is a property of the bank, not of this code.
 *
 * <p>Deliberately read-only. It never repairs anything — unwinding a settlement automatically, on a
 * timer, on the strength of "this looks stuck", is how one dropped message becomes a double refund.
 * It reports, and a human decides.
 */
@Service
public class SettlementHealthService {

    private final AccountingTransactionRepository transactions;
    private final Duration pendingThreshold;
    private final Duration uncreditedThreshold;

    public SettlementHealthService(
            AccountingTransactionRepository transactions,
            /*
             * Generous next to a healthy settlement, which completes in seconds. The number is not
             * trying to catch a slow bank — it is trying to be so far past normal that anything
             * over it is worth waking someone for.
             */
            @Value("${delivery.accounting.health.pending-threshold:15m}") Duration pendingThreshold,
            /*
             * Tighter, because this one means money has already left a customer. The cost of
             * looking at a settlement that turns out to have been fine is a minute of somebody's
             * attention; the cost of not looking is a customer out of pocket with nobody paid.
             */
            @Value("${delivery.accounting.health.uncredited-threshold:5m}")
            Duration uncreditedThreshold) {
        this.transactions = transactions;
        this.pendingThreshold = pendingThreshold;
        this.uncreditedThreshold = uncreditedThreshold;
    }

    /**
     * Legs the saga has been waiting on for longer than it should have to.
     *
     * <p>Includes the acute case below, and a good deal that is less alarming — a merchant credit
     * waiting behind a bank outage is stuck but not dangerous, because no money has moved yet.
     */
    @Transactional(readOnly = true)
    public long stuckLegs() {
        return transactions.countByStatusAndCreatedAtBefore(
                com.delivery.accounting.domain.AccountingTransaction.Status.PENDING,
                Instant.now().minus(pendingThreshold));
    }

    /**
     * Orders where the customer paid and nobody has been paid.
     *
     * <p>The number that matters. Anything above zero here is money the platform is holding that it
     * has no business holding, and every minute it stays that way is a minute a customer is out of
     * pocket for goods the merchant has not been paid for.
     */
    @Transactional(readOnly = true)
    public long debitedWithoutCounterpart() {
        return transactions.countDebitedWithoutCounterpartOlderThan(
                Instant.now().minus(uncreditedThreshold));
    }

    public Duration getPendingThreshold() {
        return pendingThreshold;
    }

    public Duration getUncreditedThreshold() {
        return uncreditedThreshold;
    }
}
