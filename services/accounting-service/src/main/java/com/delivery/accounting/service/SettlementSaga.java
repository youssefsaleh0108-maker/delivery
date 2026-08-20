package com.delivery.accounting.service;

import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransaction.Status;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CoreBankingSyncLog;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;

/**
 * Advances a settlement as the bank answers, and unwinds it when it cannot be completed.
 *
 * <p>The saga has three moves and they are ordered by cost of getting them wrong:
 *
 * <ol>
 *   <li><strong>The debit posted</strong> — release the credits. Until this point the platform has
 *       collected money and paid nobody, which is recoverable; the reverse is not.</li>
 *   <li><strong>The debit failed permanently</strong> — abandon the credits. Nothing was collected,
 *       so nothing must be paid out. This is the case a naive implementation gets wrong by firing
 *       all three legs at once and crediting a merchant for money that never arrived.</li>
 *   <li><strong>A credit failed after the debit posted</strong> — refund the customer. The platform
 *       is holding money it cannot distribute, and leaving it there silently is the worst
 *       outcome available.</li>
 * </ol>
 *
 * <p>A <em>retryable</em> failure is none of those. The connector is still trying, so the leg stays
 * PENDING and the saga does nothing — treating a slow bank as a failed one would compensate a
 * settlement that was about to succeed.
 */
@Service
public class SettlementSaga {

    private static final Logger log = LoggerFactory.getLogger(SettlementSaga.class);

    private final AccountingTransactionRepository transactions;
    private final CoreBankingSyncLogRepository syncLog;
    private final SettlementService settlements;
    private final BankPostingPublisher postings;

    public SettlementSaga(AccountingTransactionRepository transactions,
                          CoreBankingSyncLogRepository syncLog,
                          SettlementService settlements,
                          BankPostingPublisher postings) {
        this.transactions = transactions;
        this.syncLog = syncLog;
        this.settlements = settlements;
        this.postings = postings;
    }

    /**
     * Applies one posting result.
     *
     * <p>Idempotent: a redelivered result for a leg that already reached a terminal state is
     * ignored, so re-processing cannot re-trigger a compensation.
     */
    @Transactional
    public void onResult(UUID transactionId, boolean success, boolean retryable, String provider,
                         String coreBankingRef, String failureReason,
                         String requestPayload, String responsePayload) {

        AccountingTransaction leg = transactions.findById(transactionId).orElse(null);
        if (leg == null) {
            // Impossible in normal operation - the row is committed before the posting is
            // published - so worth a warning rather than a silent skip.
            log.warn("Posting result for unknown transaction {}", transactionId);
            return;
        }

        // Written whatever happens, and before the branch below: the sync log is the record of the
        // conversation, not just of the successful half of it.
        syncLog.save(new CoreBankingSyncLog(leg.getId(), provider, requestPayload, responsePayload,
                outcomeOf(success, retryable)));

        if (leg.isTerminal()) {
            log.debug("Ignoring redelivered result for {} already at {}", transactionId, leg.getStatus());
            return;
        }

        if (success) {
            leg.markPosted(coreBankingRef);
            transactions.save(leg);
            onLegPosted(leg);
            return;
        }

        if (retryable) {
            // Still in flight. Recording the reason without moving off PENDING is what stops the
            // reconciliation view showing a slow bank as a lost settlement.
            leg.markRetrying(failureReason);
            transactions.save(leg);
            log.info("Transaction {} will be retried: {}", transactionId, failureReason);
            return;
        }

        leg.markFailed(failureReason);
        transactions.save(leg);
        onLegFailed(leg);
    }

    private void onLegPosted(AccountingTransaction leg) {
        if (leg.getLeg() == Leg.CUSTOMER_REFUND) {
            // The compensation completed. The settlement is unwound and closed.
            log.info("Order {} refunded and unwound", leg.getOrderId());
            return;
        }

        List<AccountingTransaction> all = transactions.findByOrderIdOrderByCreatedAt(leg.getOrderId());
        // isSettled, not POSTED: a cash order's collection leg is discharged at the door and the
        // bank never sees it, so testing for POSTED would mean no cash order was ever "fully
        // settled" however well it went.
        if (all.stream().allMatch(AccountingTransaction::isSettled)) {
            log.info("Order {} fully settled", leg.getOrderId());
            return;
        }

        // One leg at a time. Deferred to after commit so the next leg is never requested against a
        // predecessor whose row failed to persist.
        afterCommit(() -> settlements.releaseNextLeg(leg.getOrderId()));
    }

    private void onLegFailed(AccountingTransaction failed) {
        List<AccountingTransaction> all = transactions.findByOrderIdOrderByCreatedAt(failed.getOrderId());

        if (failed.getLeg() == Leg.CUSTOMER_DEBIT) {
            // Nothing was collected, so nothing may be paid out. Abandoning the credits rather
            // than leaving them PENDING keeps them out of the "stuck, chase this" view — they are
            // not stuck, they are cancelled.
            for (AccountingTransaction leg : all) {
                if (leg.getDirection() == Direction.CREDIT && leg.getStatus() == Status.PENDING) {
                    leg.markAbandoned("customer debit failed: " + failed.getFailureReason());
                    transactions.save(leg);
                }
            }
            log.warn("Order {} could not be settled - customer debit refused: {}",
                    failed.getOrderId(), failed.getFailureReason());
            return;
        }

        if (failed.getLeg() == Leg.CUSTOMER_REFUND) {
            // The compensation itself failed. Nothing further is automatic — this is money the
            // platform is holding and cannot return, and it needs a person.
            log.error("REFUND FAILED for order {}: {}. Manual intervention required.",
                    failed.getOrderId(), failed.getFailureReason());
            return;
        }

        if (failed.getLeg() == Leg.PLATFORM_COMMISSION) {
            // Explicitly NOT a refund. Because the legs are sequenced, reaching here means the
            // customer was debited and the payee — merchant or rider — was paid. The order settled
            // correctly from both their points of view, and only the platform's own cut is missing.
            // Refunding the customer now would take money back from someone already paid, which is
            // a far worse outcome than the platform being short its commission. Left FAILED for an
            // operator to re-post.
            log.error("Commission not collected for order {}: {}. Customer and payee are "
                    + "settled correctly; this is platform revenue to re-post.",
                    failed.getOrderId(), failed.getFailureReason());
            return;
        }

        // The payee credit failed after the debit posted — the merchant on a basket, the rider on
        // an errand. Either way the platform is holding money it cannot pass on, so refund the
        // customer for whatever was actually collected.
        //
        // An errand makes this worse in a way worth naming: on a Butler BUY the rider has already
        // spent their own money on the goods, so a refunded customer leaves the rider genuinely out
        // of pocket with no automatic recourse. The refund is still right — the platform must not
        // keep money it cannot distribute — but the reconciliation view is where somebody has to
        // notice and make the rider whole.
        AccountingTransaction debit = all.stream()
                .filter(t -> t.getLeg() == Leg.CUSTOMER_DEBIT)
                .findFirst()
                .orElse(null);

        if (debit == null || debit.getStatus() != Status.POSTED) {
            log.warn("Credit {} failed but no posted debit to compensate for order {}",
                    failed.getId(), failed.getOrderId());
            return;
        }

        boolean alreadyRefunding = all.stream().anyMatch(t -> t.getLeg() == Leg.CUSTOMER_REFUND);
        if (alreadyRefunding) {
            // Both credits can fail; one refund is enough, and a second would return the money
            // twice. The unique constraint on (order_id, leg) would catch it, but not quietly.
            log.info("Order {} is already being refunded", failed.getOrderId());
            return;
        }

        // Abandon whatever is still pending: it will never be paid now.
        for (AccountingTransaction leg : all) {
            if (leg.getDirection() == Direction.CREDIT && leg.getStatus() == Status.PENDING) {
                leg.markAbandoned("settlement unwound after " + failed.getLeg() + " failed");
                transactions.save(leg);
            }
        }

        AccountingTransaction refund = new AccountingTransaction(
                failed.getOrderId(), Leg.CUSTOMER_REFUND, debit.getAccountRef(),
                debit.getAmount(), debit.getCurrency(), Direction.CREDIT, debit.getCorrelationId());
        transactions.save(refund);
        debit.markCompensated();
        transactions.save(debit);

        log.warn("Order {} unwound: {} failed ({}), refunding {} to {}",
                failed.getOrderId(), failed.getLeg(), failed.getFailureReason(),
                refund.getAmount(), refund.getAccountRef());

        afterCommit(() -> postings.request(refund));
    }

    private static CoreBankingSyncLog.Outcome outcomeOf(boolean success, boolean retryable) {
        if (success) {
            return CoreBankingSyncLog.Outcome.POSTED;
        }
        return retryable ? CoreBankingSyncLog.Outcome.RETRYABLE : CoreBankingSyncLog.Outcome.REJECTED;
    }

    private static void afterCommit(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                action.run();
            }
        });
    }
}
