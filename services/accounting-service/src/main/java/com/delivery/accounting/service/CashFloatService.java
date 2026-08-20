package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * Banking the takings.
 *
 * <p>The other half of the float. A cash collection creates an obligation and deliberately never
 * touches a bank, because no bank saw it — but handing the notes over at the end of a shift
 * <strong>is</strong> a real movement, and this is where it is recorded as one.
 *
 * <p>The asymmetry is the point and worth stating: collection is a ledger fact, remittance is a
 * bank posting. Treating both the same way is what broke the first attempt at cash entirely.
 */
@Service
public class CashFloatService {

    private static final Logger log = LoggerFactory.getLogger(CashFloatService.class);

    private final CashFloatRepository floatEntries;
    private final AccountingTransactionRepository transactions;
    private final BankPostingPublisher postings;
    private final String platformAccount;
    private final String currency;

    public CashFloatService(CashFloatRepository floatEntries,
                            AccountingTransactionRepository transactions,
                            BankPostingPublisher postings,
                            @Value("${delivery.accounting.platform-account:ACC-PLATFORM}")
                            String platformAccount,
                            @Value("${delivery.accounting.currency:USD}") String currency) {
        this.floatEntries = floatEntries;
        this.transactions = transactions;
        this.postings = postings;
        this.platformAccount = platformAccount;
        this.currency = currency;
    }

    /** What one holder is still carrying. */
    @Transactional(readOnly = true)
    public BigDecimal outstandingFor(String holderRef) {
        return floatEntries.outstandingTotalFor(holderRef);
    }

    /**
     * Records that a holder has banked everything they were carrying.
     *
     * <p><strong>Everything, not an amount.</strong> A partial remittance would mean splitting a
     * collection across two settlements — an entry half-cleared — and that needs a model where a
     * collection can be partly discharged. Rather than fake it by clearing whole entries and
     * quietly leaving the arithmetic wrong, this settles the whole balance or nothing, and a
     * partial hand-over is a gap named here rather than a bug discovered later.
     *
     * <p>The posting credits the platform, and only the platform. The holder's side moved no bank
     * account: they handed over physical notes, which is exactly the thing the float exists to
     * represent.
     *
     * @return the remittance, or empty when there was nothing outstanding
     */
    @Transactional
    public java.util.Optional<Remittance> remitAll(String holderRef, String correlationId) {
        List<CashFloatEntry> outstanding = floatEntries.outstandingFor(holderRef);
        if (outstanding.isEmpty()) {
            log.debug("{} is carrying nothing; no remittance recorded", holderRef);
            return java.util.Optional.empty();
        }

        BigDecimal total = outstanding.stream()
                .map(CashFloatEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        CashFloatEntry.HolderKind kind = outstanding.get(0).getHolderKind();
        CashFloatEntry remittance =
                floatEntries.save(CashFloatEntry.remitted(holderRef, kind, total, currency));

        // Cleared by the remittance's own id, so the audit trail runs both ways: from a settlement
        // to the day it was banked, and from a banking to everything it covered.
        for (CashFloatEntry collected : outstanding) {
            collected.clearedBy(remittance.getId());
        }

        // The remittance carries its own id as the transaction's order id. A remittance belongs to
        // no single order — it covers many — and the column is not nullable, so the alternative is
        // pretending it belongs to one of them.
        AccountingTransaction posting = new AccountingTransaction(
                remittance.getId(), Leg.CASH_REMITTANCE, platformAccount,
                total, currency, Direction.CREDIT, correlationId);
        transactions.save(posting);

        log.info("{} banked {} covering {} collections", holderRef, total, outstanding.size());

        afterCommit(() -> postings.request(posting));
        return java.util.Optional.of(
                new Remittance(remittance.getId(), holderRef, total, outstanding.size()));
    }

    /** What a caller gets back: the id to quote, and what it covered. */
    public record Remittance(UUID id, String holderRef, BigDecimal amount, int collections) {
    }

    /**
     * Runs once the surrounding transaction has committed.
     *
     * <p>Same reason as the settlement path: publishing first and then rolling back would have the
     * bank move money against a remittance this service has no record of.
     */
    private void afterCommit(Runnable action) {
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
