package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

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

    /**
     * The start of every request key a pay run records a deduction under — {@code payroll-} and a
     * hash of the run and the rider ({@code CarrierPayrollService.payrollKey}) — and of no other key.
     *
     * <p>Reserved because a repeated key is answered with whatever it recorded first. The run's id
     * and the rider are both on the company's own pages, so the key can be worked out; a counter
     * hand-over sent under it that committed just before the run was approved would otherwise be
     * replayed as the run's deduction, and the rider would lose the same notes twice — once at the
     * counter and once from their pay. So no route a person calls accepts the prefix, this service
     * refuses it on anything but a payroll deduction, and a replay must repeat the method too.
     */
    public static final String PAYROLL_KEY_PREFIX = "payroll-";

    /** Whether a request key is one only payroll records under. Case aside: "PAYROLL-" is one. */
    public static boolean isPayrollKey(String requestKey) {
        return requestKey != null && requestKey.regionMatches(true, 0, PAYROLL_KEY_PREFIX, 0,
                PAYROLL_KEY_PREFIX.length());
    }

    /** What one holder is still carrying, as one kind of holder. */
    @Transactional(readOnly = true)
    public BigDecimal outstandingFor(String holderRef, CashFloatEntry.HolderKind holderKind) {
        return floatEntries.outstandingTotalFor(holderRef, holderKind);
    }

    /**
     * What every shop holding pickup cash owes out of its till right now, by shop (V52).
     *
     * <p>Two reads however many shops there are: every shop's outstanding collections, and the legs
     * on those orders. The Back Office's list shows it beside each till, so the operator confirms the
     * figure a shop actually pays — the platform's part — and not the till, most of which is the
     * shop's own share. See {@link ShopTill}.
     */
    @Transactional(readOnly = true)
    public Map<String, ShopTill> shopTills() {
        List<CashFloatEntry> rows = floatEntries.heldByKind(CashFloatEntry.HolderKind.MERCHANT);
        if (rows.isEmpty()) {
            return Map.of();
        }
        List<AccountingTransaction> legs = transactions.findByOrderIdIn(orderIdsOf(rows));
        Map<String, List<CashFloatEntry>> byShop = rows.stream().collect(Collectors.groupingBy(
                CashFloatEntry::getHolderRef, LinkedHashMap::new, Collectors.toList()));
        Map<String, ShopTill> tills = new LinkedHashMap<>();
        byShop.forEach((shop, till) -> tills.put(shop, ShopTill.of(shop, till, legs)));
        return tills;
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
     * {@link #remit(String, String, BigDecimal, Recorded, CashFloatEntry.HolderKind)}, not told which
     * kind of holder is paying — the shape of every call made before a shop could hold cash.
     */
    @Transactional
    public Optional<Remittance> remit(String holderRef, String correlationId, BigDecimal expected,
                                      Recorded recorded) {
        return remit(holderRef, correlationId, expected, recorded, null);
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
     * <p><strong>Whose cash (V52).</strong> One Keycloak subject can hold cash as more than one kind
     * of holder — a shop that also delivers has a till and a rider's bag — and the two are settled on
     * different terms. Told the kind, this clears only that kind's cash. Not told, it clears what the
     * subject holds when that is all of one kind, exactly as before, and refuses when it is not,
     * rather than record the till and the bag as one payment of whichever kind happened to be oldest.
     *
     * <p><strong>Only cash owed to the platform (RECON-03).</strong> A delivery company's rider owes
     * the notes from the company's jobs to the company, which records its own hand-over
     * ({@link #handOver}); they are never cleared here. Banking a rider clears their platform-fleet
     * cash, and {@code expected} is checked against that figure alone.
     *
     * <p><strong>A shop keeps its share.</strong> A shop's till is cleared against what the shop owes
     * out of it, never against the till ({@link ShopTill}): what it pays is REMITTED and posted as
     * every payment is, and the share it keeps is RETAINED and posted nowhere, because none of it
     * reached the platform. And a shop's payment is only ever recorded against a figure the operator
     * confirmed: a confirmation naming no figure cannot say whether the operator was looking at the
     * till or at the commission, and those are two different payments.
     *
     * @param expected   what the operator was looking at when they confirmed, or null to skip the
     *                   check — which a shop's till never may. A delivery company's balance grows
     *                   every time one of its riders hands over, so "they paid what I saw" and "they
     *                   paid everything" can differ between page load and click — and the one the
     *                   operator counted is the one to record. For a shop it is what the shop owes
     * @param holderKind which of the subject's cash is being paid in, or null when the caller did not
     *                   say
     * @return the remittance, or empty when there was nothing outstanding
     * @throws AmountChangedException      the balance is not {@code expected}; nothing was recorded
     * @throws RequestKeyReusedException   the key already recorded something else
     * @throws HolderKindRequiredException not told the kind, and the subject holds more than one
     * @throws AmountRequiredException     a shop's till, with no amount confirmed
     */
    @Transactional
    public Optional<Remittance> remit(String holderRef, String correlationId, BigDecimal expected,
                                      Recorded recorded, CashFloatEntry.HolderKind holderKind) {
        Recorded who = recorded == null ? Recorded.nobody() : recorded;
        if (isPayrollKey(who.requestKey())) {
            throw new IllegalArgumentException("That request key is kept for pay runs");
        }

        Optional<Remittance> replay = replayRemittance(holderRef, holderKind, who);
        if (replay.isPresent()) {
            return replay;
        }

        List<CashFloatEntry> outstanding = holderKind == null
                ? floatEntries.outstandingFor(holderRef)
                : floatEntries.outstandingFor(holderRef, holderKind);

        // Asked again now the rows are locked: a twin of this request holding the same key may have
        // committed while this one waited on its locks, and it recorded the payment already.
        replay = replayRemittance(holderRef, holderKind, who);
        if (replay.isPresent()) {
            return replay;
        }

        if (outstanding.stream().map(CashFloatEntry::getHolderKind).distinct().count() > 1) {
            throw new HolderKindRequiredException();
        }
        boolean shopsTill = holderKind == null
                ? !outstanding.isEmpty()
                        && outstanding.get(0).getHolderKind() == CashFloatEntry.HolderKind.MERCHANT
                : holderKind == CashFloatEntry.HolderKind.MERCHANT;
        if (shopsTill) {
            return payInTill(holderRef, outstanding, correlationId, expected, who);
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
     * @throws IllegalArgumentException  a missing party, an amount that is not a positive sum, or a
     *                                   pay run's key without a pay run's method (or the reverse)
     * @throws AmountChangedException    the rider does not hold exactly {@code expected} for this
     *                                   company; nothing was recorded
     * @throws RequestKeyReusedException the key already recorded something else — another rider,
     *                                   another company or another method
     */
    @Transactional
    public Handover handOver(String carrierRef, String riderRef, BigDecimal expected,
                             Recorded recorded) {
        return handOver(carrierRef, riderRef, expected, recorded, null);
    }

    /**
     * {@link #handOver(String, String, BigDecimal, Recorded)}, clearing only the cash the rider
     * collected before {@code collectedBefore}: a pay run's deduction.
     *
     * <p><strong>Why a cut-off.</strong> A pay run nets the cash its period produced, and riders keep
     * working after a period ends. Against everything a rider holds right now, the payslip's figure
     * went stale with every cash delivery made while the approver was looking, and approval kept
     * refusing through the working day. What a rider collected up to the period's end and still holds
     * stops growing when the period closes: it can only fall, when the rider hands it over at the hub,
     * and that is a real change the approver has to see. Cash collected later is not on the payslip,
     * so it stays in the rider's bag, for the hub or the next run.
     *
     * <p><strong>Otherwise the same door.</strong> Every row the rider holds for the company is locked,
     * in the same order as a counter hand-over locks them, so the two wait on each other exactly as
     * two counters do; {@code expected} is checked against what is cleared; a repeated key replays.
     * Whole rows only, by when each was written, so no collection is ever split.
     *
     * @param collectedBefore exclusive; null clears everything the rider holds for the company
     */
    @Transactional
    public Handover handOver(String carrierRef, String riderRef, BigDecimal expected,
                             Recorded recorded, Instant collectedBefore) {
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
        // A pay run's key and a pay run's method go together or not at all: see PAYROLL_KEY_PREFIX.
        boolean payroll = who.method() == CashFloatEntry.Method.PAYROLL_DEDUCTION;
        if (payroll != isPayrollKey(who.requestKey())) {
            throw new IllegalArgumentException(payroll
                    ? "A payroll deduction is recorded under its pay run's key"
                    : "That request key is kept for pay runs");
        }

        Optional<Handover> replay = replayHandover(carrierRef, riderRef, who);
        if (replay.isPresent()) {
            return replay.get();
        }

        List<CashFloatEntry> locked = floatEntries.lockHeldForCarrier(riderRef, carrierRef);

        // See remit(): the twin of this request may have committed while this one waited.
        replay = replayHandover(carrierRef, riderRef, who);
        if (replay.isPresent()) {
            return replay.get();
        }

        List<CashFloatEntry> held = collectedBefore == null
                ? locked
                : locked.stream().filter(row -> writtenBefore(row, collectedBefore)).toList();
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

    /**
     * A shop paying in its till: the platform's part, with its own share kept. See
     * {@link #remit(String, String, BigDecimal, Recorded, CashFloatEntry.HolderKind)} and
     * {@link ShopTill}.
     *
     * <p>Two rows, and the pickups are cleared by the one that says what reached the platform: the
     * platform's part is REMITTED and posted, as every holder's payment is, and the shop's share is
     * RETAINED and posted nowhere. Where a promotion left none of the till the platform's there is
     * nothing to pay and nothing to post, so the RETAINED row alone clears the pickups — and carries
     * the request key, so that a second press still finds the first.
     */
    private Optional<Remittance> payInTill(String shopRef, List<CashFloatEntry> till,
                                           String correlationId, BigDecimal expected,
                                           Recorded who) {
        ShopTill owing = ShopTill.of(shopRef, till,
                till.isEmpty() ? List.of() : transactions.findByOrderIdIn(orderIdsOf(till)));
        if (expected != null && owing.owed().compareTo(money(expected)) != 0) {
            throw new AmountChangedException(owing.owed());
        }
        if (till.isEmpty()) {
            log.debug("{} holds nothing from its counter; no payment recorded", shopRef);
            return Optional.empty();
        }
        if (expected == null) {
            throw new AmountRequiredException();
        }

        CashFloatEntry paid = owing.owed().signum() > 0
                ? floatEntries.save(CashFloatEntry.remitted(shopRef,
                        CashFloatEntry.HolderKind.MERCHANT, owing.owed(), currency, who))
                : null;
        CashFloatEntry kept = owing.retained().signum() > 0
                ? floatEntries.save(CashFloatEntry.retained(shopRef, owing.retained(), currency,
                        who.by(), paid == null ? who.requestKey() : null))
                : null;
        UUID clearing = paid != null ? paid.getId() : kept.getId();
        for (CashFloatEntry collected : till) {
            collected.clearedBy(clearing);
        }

        if (paid != null) {
            // As on every remittance: the payment's own id stands in for an order, and the bank is
            // asked only once this has committed.
            AccountingTransaction posting = new AccountingTransaction(
                    paid.getId(), Leg.CASH_REMITTANCE, platformAccount,
                    owing.owed(), currency, Direction.CREDIT, correlationId);
            transactions.save(posting);
            afterCommit(() -> postings.request(posting));
        }

        log.info("{} paid {} out of a till of {} and kept {} as its share, covering {} pickups",
                shopRef, owing.owed(), owing.held(), owing.retained(), till.size());
        return Optional.of(new Remittance(clearing, shopRef, owing.owed(), till.size(), false,
                owing.retained()));
    }

    /**
     * What a remittance caller gets back: the id to quote, and what it covered.
     *
     * @param amount   what reached the platform
     * @param retained what a shop kept of its till as its own share (V52); zero for anybody else
     */
    public record Remittance(UUID id, String holderRef, BigDecimal amount, int collections,
                             boolean replayed, BigDecimal retained) {

        public Remittance(UUID id, String holderRef, BigDecimal amount, int collections) {
            this(id, holderRef, amount, collections, false);
        }

        public Remittance(UUID id, String holderRef, BigDecimal amount, int collections,
                          boolean replayed) {
            this(id, holderRef, amount, collections, replayed, BigDecimal.ZERO);
        }
    }

    /**
     * Not told which kind of holder is paying, when the account holds cash as more than one (V52): a
     * shop that also delivers, with a till and a rider's bag. Clearing both as one payment would book
     * the till as a rider's banking or the bag as a shop's, so nothing was recorded.
     */
    public static class HolderKindRequiredException extends RuntimeException {
        public HolderKindRequiredException() {
            super("This account holds cash as more than one kind of holder; say which one is paying");
        }
    }

    /**
     * A shop's till, with no amount confirmed (V52). A shop pays the platform its commission, not its
     * till, and a confirmation that named no figure cannot say which of the two the operator saw.
     */
    public static class AmountRequiredException extends RuntimeException {
        public AmountRequiredException() {
            super("A shop's payment is recorded against the amount it owes; confirm that amount");
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

    private Optional<Remittance> replayRemittance(String holderRef,
                                                  CashFloatEntry.HolderKind holderKind,
                                                  Recorded who) {
        if (who.requestKey() == null) {
            return Optional.empty();
        }
        return floatEntries.findByRequestKey(who.requestKey()).map(previous -> {
            // A double press repeats everything it sent; a different method is a different request.
            // A shop's payment that left none of its till the platform's is keyed on the share it
            // kept (see payInTill), which records no method because nothing was handed over.
            boolean paid = previous.getEntryKind() == CashFloatEntry.Kind.REMITTED;
            boolean keptOnly = previous.getEntryKind() == CashFloatEntry.Kind.RETAINED;
            if (!(paid || keptOnly)
                    || !holderRef.equals(previous.getHolderRef())
                    || (holderKind != null && previous.getHolderKind() != holderKind)
                    || (paid && previous.getMethod() != who.method())) {
                throw new RequestKeyReusedException();
            }
            BigDecimal amount = paid ? previous.getAmount() : money(BigDecimal.ZERO);
            // What a shop kept is what its payment cleared less what it paid: the RETAINED row
            // written beside the payment says the same, and this needs no link between the two.
            BigDecimal retained = previous.getHolderKind() == CashFloatEntry.HolderKind.MERCHANT
                    ? money(orZero(floatEntries.clearedTotal(previous.getId())).subtract(amount))
                    : BigDecimal.ZERO;
            return new Remittance(previous.getId(), holderRef, amount,
                    clearedBy(previous.getId()), true, retained);
        });
    }

    private static List<UUID> orderIdsOf(List<CashFloatEntry> rows) {
        return rows.stream().map(CashFloatEntry::getOrderId).distinct().toList();
    }

    private static BigDecimal orZero(BigDecimal amount) {
        return amount == null ? BigDecimal.ZERO : amount;
    }

    private Optional<Handover> replayHandover(String carrierRef, String riderRef, Recorded who) {
        if (who.requestKey() == null) {
            return Optional.empty();
        }
        return floatEntries.findByRequestKey(who.requestKey()).map(previous -> {
            // The method as well as the parties: a counter hand-over is never a pay run's deduction,
            // whatever key it was sent under (see PAYROLL_KEY_PREFIX).
            if (previous.getEntryKind() != CashFloatEntry.Kind.TRANSFERRED
                    || !riderRef.equals(previous.getHolderRef())
                    || !carrierRef.equals(previous.getCarrierRef())
                    || previous.getMethod() != who.method()) {
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

    /**
     * Whether a row was written before the cut-off. A row with no time yet has not been read back
     * from the database — it was written in this transaction, so now — and is never before one.
     */
    static boolean writtenBefore(CashFloatEntry row, Instant cutOff) {
        return row.getCreatedAt() != null && row.getCreatedAt().isBefore(cutOff);
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
