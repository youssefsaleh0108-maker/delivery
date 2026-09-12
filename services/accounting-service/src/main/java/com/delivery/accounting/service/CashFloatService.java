package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
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
import com.delivery.accounting.domain.CashFloatEntry.Recorded;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * Banking the takings, and handing them over.
 *
 * <p>The other half of the float. A cash collection creates an obligation and deliberately never
 * touches a bank, because no bank saw it — but handing the notes over at the end of a shift
 * <strong>is</strong> a real movement, and this is where it is recorded as one.
 *
 * <p>The asymmetry is the point and worth stating: collection is a ledger fact, remittance is a
 * bank posting. Treating both the same way is what broke the first attempt at cash entirely.
 *
 * <p><strong>Two kinds of hand-over, and only one reaches the platform.</strong> A remittance is
 * cash arriving at the platform, from one of its own riders or from a delivery company, and it posts
 * a {@code CASH_REMITTANCE}. A company's rider handing their bag to the company's hub is a transfer
 * of custody inside the float: the platform has received nothing, so nothing is posted — the company
 * simply becomes the holder, and its later remittance is the posting. Every note is therefore posted
 * exactly once however many hands it passes through.
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
     * Records that a holder has banked everything they were carrying, with nobody named and no
     * amount checked — the shape every remittance had before V50.
     */
    @Transactional
    public Optional<Remittance> remitAll(String holderRef, String correlationId) {
        return remit(holderRef, correlationId, null, Recorded.nobody());
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
     * <p><strong>Safe to press twice.</strong> The outstanding rows are read under a row lock, so a
     * second call made at the same moment waits for the first, finds them cleared and records
     * nothing; a repeated {@code requestKey} answers with the first remittance instead of a second.
     *
     * @param expected what the operator was looking at when they confirmed, or null to skip the
     *                 check. A delivery company's balance grows every time one of its riders hands
     *                 over, so "they paid what I saw" and "they paid everything" can differ between
     *                 page load and click — and the one the operator counted is the one to record
     * @return the remittance, or empty when there was nothing outstanding
     * @throws AmountChangedException    the balance is not {@code expected}; nothing was recorded
     * @throws RequestKeyReusedException the key already recorded something else
     */
    @Transactional
    public Optional<Remittance> remit(String holderRef, String correlationId, BigDecimal expected,
                                      Recorded recorded) {
        Recorded who = recorded == null ? Recorded.nobody() : recorded;

        Optional<Remittance> replay = replayRemittance(holderRef, who.requestKey());
        if (replay.isPresent()) {
            return replay;
        }

        List<CashFloatEntry> outstanding = floatEntries.outstandingFor(holderRef);

        // Asked again now the rows are locked: a twin of this request holding the same key may have
        // committed while this one waited on its locks, and it recorded the payment already.
        replay = replayRemittance(holderRef, who.requestKey());
        if (replay.isPresent()) {
            return replay;
        }

        BigDecimal total = sum(outstanding);
        if (expected != null && total.compareTo(money(expected)) != 0) {
            throw new AmountChangedException(total);
        }
        if (outstanding.isEmpty()) {
            log.debug("{} is carrying nothing; no remittance recorded", holderRef);
            return Optional.empty();
        }

        CashFloatEntry.HolderKind kind = outstanding.get(0).getHolderKind();
        CashFloatEntry remittance =
                floatEntries.save(CashFloatEntry.remitted(holderRef, kind, total, currency, who));

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
        return Optional.of(
                new Remittance(remittance.getId(), holderRef, total, outstanding.size()));
    }

    /**
     * A delivery company's rider handing the cash they collected for it to the company.
     *
     * <p><strong>A move of custody, and it balances by construction.</strong> The rider's rows for
     * this company are cleared by one {@code TRANSFERRED} row, and the company receives one custody
     * copy per cleared order at the same amount — same orders, same cents, one transaction. The
     * platform-wide outstanding total does not move by a cent, the rider's goes to zero for this
     * company, and the company's rises by exactly what the rider's fell by. No posting: no money
     * reached the platform, and the company's remittance is where it will.
     *
     * <p><strong>Only this company's cash.</strong> What the same rider holds from the platform's own
     * fleet, or from a company they rode for before, is somebody else's to collect and is left
     * exactly where it is.
     *
     * <p><strong>The amount the hub counted, or nothing.</strong> {@code expected} is the figure on
     * screen when the manager confirmed. If the rider collected more since the page loaded, clearing
     * it all would record notes nobody counted, so this refuses with the current figure and the
     * manager counts again. And it is safe against a double press: the rows are locked, a repeated
     * {@code requestKey} answers with the first hand-over, and a second press with no key finds the
     * rows already cleared and is refused rather than recorded.
     *
     * @throws IllegalArgumentException  a missing party, or an amount that is not a positive sum
     * @throws AmountChangedException    the rider does not hold exactly {@code expected} for this
     *                                   company; nothing was recorded
     * @throws RequestKeyReusedException the key already recorded something else
     */
    @Transactional
    public Handover handOver(String carrierRef, String riderRef, BigDecimal expected,
                             Recorded recorded) {
        if (carrierRef == null || carrierRef.isBlank() || riderRef == null || riderRef.isBlank()) {
            throw new IllegalArgumentException("A hand-over needs a company and a rider");
        }
        // Trailing zeros stripped before the scale is read: "485.000" is a whole number of cents and
        // a client that pads its figure must not be refused for it, while "10.001" is not.
        if (expected == null || expected.signum() <= 0
                || expected.stripTrailingZeros().scale() > 2) {
            throw new IllegalArgumentException(
                    "The amount handed over must be more than nothing, to the cent");
        }
        Recorded who = recorded == null ? Recorded.nobody() : recorded;

        Optional<Handover> replay = replayHandover(carrierRef, riderRef, who.requestKey());
        if (replay.isPresent()) {
            return replay.get();
        }

        List<CashFloatEntry> held = floatEntries.lockHeldForCarrier(riderRef, carrierRef);

        // See remit(): the twin of this request may have committed while this one waited.
        replay = replayHandover(carrierRef, riderRef, who.requestKey());
        if (replay.isPresent()) {
            return replay.get();
        }

        BigDecimal total = sum(held);
        if (held.isEmpty() || total.compareTo(money(expected)) != 0) {
            throw new AmountChangedException(total);
        }

        CashFloatEntry transfer = floatEntries.save(
                CashFloatEntry.transferred(riderRef, carrierRef, total, currency, who));

        List<CashFloatEntry> custody = new ArrayList<>(held.size());
        for (CashFloatEntry collected : held) {
            collected.clearedBy(transfer.getId());
            custody.add(CashFloatEntry.custodyOf(carrierRef, collected.getOrderId(),
                    collected.getAmount(), collected.getCurrency(), transfer.getId()));
        }

        // The invariant, checked rather than assumed: what the company now holds is exactly what the
        // rider no longer does. It cannot fail with the loop above, and that is the point of writing
        // it down — the day somebody edits the loop, this is what notices.
        BigDecimal moved = sum(custody);
        if (moved.compareTo(total) != 0) {
            throw new IllegalStateException("A hand-over of " + total + " would give the company "
                    + moved + "; nothing was recorded");
        }
        floatEntries.saveAll(custody);
        // Flushed here so a duplicate key or order surfaces from this call, where the caller can say
        // something true about it, rather than at commit.
        floatEntries.flush();

        log.info("{} handed {} covering {} collections to company {}",
                riderRef, total, held.size(), carrierRef);

        return new Handover(transfer.getId(), riderRef, carrierRef, total, held.size(),
                who.method(), who.note(), who.by(), Instant.now(), false);
    }

    /** What a remittance caller gets back: the id to quote, and what it covered. */
    public record Remittance(UUID id, String holderRef, BigDecimal amount, int collections,
                             boolean replayed) {

        public Remittance(UUID id, String holderRef, BigDecimal amount, int collections) {
            this(id, holderRef, amount, collections, false);
        }
    }

    /**
     * A recorded hand-over from a rider to their company.
     *
     * @param replayed true when this is the answer to a repeated request key, not a new record
     */
    public record Handover(UUID id, String riderRef, String carrierRef, BigDecimal amount,
                           int collections, CashFloatEntry.Method method, String note,
                           String recordedBy, Instant at, boolean replayed) {
    }

    /**
     * The balance is not what the caller confirmed.
     *
     * <p>Carries the current figure so the page can show it: "the amount changed" with no new amount
     * is an instruction nobody can follow.
     */
    public static class AmountChangedException extends RuntimeException {
        private final BigDecimal current;

        public AmountChangedException(BigDecimal current) {
            super("The amount outstanding is now " + current);
            this.current = current;
        }

        public BigDecimal current() {
            return current;
        }
    }

    /** A request key that already recorded something different — a different rider or holder. */
    public static class RequestKeyReusedException extends RuntimeException {
        public RequestKeyReusedException() {
            super("That request key has already been used for something else");
        }
    }

    private Optional<Remittance> replayRemittance(String holderRef, String requestKey) {
        if (requestKey == null) {
            return Optional.empty();
        }
        return floatEntries.findByRequestKey(requestKey).map(previous -> {
            if (previous.getEntryKind() != CashFloatEntry.Kind.REMITTED
                    || !holderRef.equals(previous.getHolderRef())) {
                throw new RequestKeyReusedException();
            }
            return new Remittance(previous.getId(), holderRef, previous.getAmount(),
                    clearedBy(previous.getId()), true);
        });
    }

    private Optional<Handover> replayHandover(String carrierRef, String riderRef,
                                              String requestKey) {
        if (requestKey == null) {
            return Optional.empty();
        }
        return floatEntries.findByRequestKey(requestKey).map(previous -> {
            if (previous.getEntryKind() != CashFloatEntry.Kind.TRANSFERRED
                    || !riderRef.equals(previous.getHolderRef())
                    || !carrierRef.equals(previous.getCarrierRef())) {
                throw new RequestKeyReusedException();
            }
            return new Handover(previous.getId(), riderRef, carrierRef, previous.getAmount(),
                    clearedBy(previous.getId()), previous.getMethod(), previous.getNote(),
                    previous.getRecordedBy(), previous.getCreatedAt(), true);
        });
    }

    /** How many collections one remittance or transfer cleared. */
    private int clearedBy(UUID id) {
        for (Object[] row : floatEntries.countClearedBy(List.of(id))) {
            if (id.equals(row[0])) {
                return ((Number) row[1]).intValue();
            }
        }
        return 0;
    }

    private static BigDecimal sum(List<CashFloatEntry> rows) {
        return money(rows.stream()
                .map(CashFloatEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add));
    }

    private static BigDecimal money(BigDecimal amount) {
        return amount.setScale(2, RoundingMode.HALF_UP);
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
