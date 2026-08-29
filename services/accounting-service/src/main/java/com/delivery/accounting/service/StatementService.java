package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.EntryType;
import com.delivery.accounting.domain.RiderLedgerEntry.PayableBy;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * Builds a counterparty's statement out of the ledger.
 *
 * <p><strong>The four kinds are not one query with a filter.</strong> A merchant is owed the goods
 * they sold less commission and nothing else. A rider is owed their earnings AND owes the platform
 * every note they took at the door — one party, two directions, and a net that can point either way.
 * A carrier is owed delivery fees on jobs whose goods it never touched. The platform's own statement
 * runs the other way round from all three. Writing that as one generic aggregation over
 * {@code transactions} was the tempting shape and it is wrong: it would silently give a rider a
 * statement that ignores their cash float, which is the single largest number on it.
 *
 * <p><strong>What is exact and what is an attribution.</strong> The NET on every statement — what
 * the platform owes, or is owed — is read straight off the legs and is exact. The decomposition into
 * "goods sold" and "commission" is not always available: the platform's leg on an order is a
 * RESIDUE, everything the customer paid that nobody else received, and on an order with several
 * payees there is nothing in the ledger that says how much of that residue each of them accounts
 * for. So the gross-up is only performed where it is provable — where this counterparty is the only
 * non-platform payee on the order — and every statement's note says which of the two it got. An
 * approximate net would be a bug; an approximate breakdown, clearly labelled, is a report.
 *
 * @see Statement for the balance property and the sign convention
 */
@Service
public class StatementService {

    private static final Logger log = LoggerFactory.getLogger(StatementService.class);

    /**
     * The most per-order rows any one statement carries.
     *
     * <p>A month of platform commission is every order on the platform, and nobody reads ten
     * thousand rows in an email. The totals are always complete — only the itemisation is trimmed,
     * and the note says so, because a truncated list that does not admit it looks like a shorter
     * month.
     */
    private static final int MAX_ENTRIES = 500;

    /**
     * The most parties one listing will build statements for.
     *
     * <p>The listing builds each row through {@link #build}, which costs a couple of queries per
     * party. Cheaper aggregation in SQL was the alternative and was rejected: it would be a second
     * implementation of every rule in this class, and the day the two disagree is the day the
     * summary screen and the statement behind it show different money.
     */
    private static final int MAX_COUNTERPARTIES = 500;

    private final AccountingTransactionRepository transactions;
    private final CashFloatRepository floatEntries;
    private final RiderLedgerRepository riderLedger;
    private final StatementDispatchRepository dispatches;
    private final CounterpartyDirectory directory;
    private final BigDecimal commissionPercentage;
    private final String currency;
    private final ZoneId zone;

    public StatementService(AccountingTransactionRepository transactions,
                            CashFloatRepository floatEntries,
                            RiderLedgerRepository riderLedger,
                            StatementDispatchRepository dispatches,
                            CounterpartyDirectory directory,
                            // Shown in the commission line's LABEL only, never used to recompute a
                            // figure. Everything on a statement is read from the legs; a percentage
                            // applied afterwards would restate history the moment the rate changed.
                            @Value("${delivery.ordering.commission-percentage:12.5}")
                            BigDecimal commissionPercentage,
                            @Value("${delivery.accounting.currency:USD}") String currency,
                            // The calendar a date range is interpreted in. One region, one zone; the
                            // same fallback the rider Earnings screen uses, and for the same reason —
                            // "August" is a different 31 days depending on where you are standing.
                            @Value("${delivery.accounting.statements.zone:UTC}") String zone) {
        this.transactions = transactions;
        this.floatEntries = floatEntries;
        this.riderLedger = riderLedger;
        this.dispatches = dispatches;
        this.directory = directory;
        this.commissionPercentage = commissionPercentage;
        this.currency = currency;
        this.zone = ZoneId.of(zone);
    }

    public ZoneId zone() {
        return zone;
    }

    public String currency() {
        return currency;
    }

    // -------------------------------------------------------------------------- one statement

    /**
     * One counterparty's statement for one period.
     *
     * @throws IllegalStateException the lines do not agree with the ledger. See {@link Statement#of}
     */
    @Transactional(readOnly = true)
    public Statement build(CounterpartyKind kind, String ref, StatementRange range) {
        Ledger ledger = ledgerFor(kind, ref, range);
        String name = directory.nameOf(kind, ref);

        return switch (kind) {
            case MERCHANT -> merchantStatement(ref, name, range, ledger);
            case CARRIER -> carrierStatement(ref, name, range, ledger);
            case RIDER -> riderStatement(ref, name, range, ledger);
            case PLATFORM -> platformStatement(ref, name, range, ledger);
        };
    }

    // ------------------------------------------------------------------------------- merchant

    /**
     * Goods sold, less the platform's commission, equals what the platform owes the shop.
     *
     * <p>The net is the {@code MERCHANT_CREDIT} legs and nothing else, so it is exact whatever else
     * happened on the order. The two gross lines are derived FROM it — goods sold is the net plus
     * the commission, never computed independently — which is what makes the column add up by
     * construction rather than by luck.
     */
    private Statement merchantStatement(String ref, String name, StatementRange range,
                                        Ledger ledger) {
        BigDecimal owed = ledger.sumOf(Leg.MERCHANT_CREDIT);
        Attribution take = ledger.platformTake(CounterpartyKind.MERCHANT, ref);

        List<Statement.Line> lines = grossUp("Goods sold", owed, take,
                ledger.orderCount() + " orders");

        List<Statement.Entry> entries = ledger.entriesFor(Leg.MERCHANT_CREDIT, take);
        return Statement.of(CounterpartyKind.MERCHANT, ref, name, range, currency,
                lines, owed, entries, ledger.orderCount(),
                note(range, ledger, take, "goods"));
    }

    // -------------------------------------------------------------------------------- carrier

    /**
     * Delivery fees on this company's jobs, less the platform's cut for finding them the work.
     *
     * <p>The {@code PROVIDER_CREDIT} leg is already net of that cut — settlement subtracts it before
     * writing the leg — so the net here is exact and needs no arithmetic at all. Whether the cut can
     * be shown as its OWN line is a different question: on an ordinary catalog order the platform's
     * leg holds the goods commission and the delivery cut added together, and nothing in the ledger
     * separates them. So the line appears on a delivery-only job, where the carrier is the only
     * payee, and does not on a catalog order — with the note saying which happened.
     */
    private Statement carrierStatement(String ref, String name, StatementRange range,
                                       Ledger ledger) {
        BigDecimal owed = ledger.sumOf(Leg.PROVIDER_CREDIT);
        Attribution take = ledger.platformTake(CounterpartyKind.CARRIER, ref);

        List<Statement.Line> lines = grossUp("Delivery fees", owed, take,
                ledger.orderCount() + " jobs");

        List<Statement.Entry> entries = ledger.entriesFor(Leg.PROVIDER_CREDIT, take);
        return Statement.of(CounterpartyKind.CARRIER, ref, name, range, currency,
                lines, owed, entries, ledger.orderCount(),
                note(range, ledger, take, "delivery fees"));
    }

    // ---------------------------------------------------------------------------------- rider

    /**
     * A rider is the only counterparty who owes and is owed at once.
     *
     * <p>Cash collected at the door is the platform's money in the rider's pocket; earnings and tips
     * are the rider's money in the platform's. Both belong on one statement and the net can point
     * either way — <strong>a rider holding cash they have not banked is a {@code THEY_OWE}</strong>,
     * and the code says so simply by subtracting, with no special case that could get it backwards.
     *
     * <p><strong>Built from {@code rider_ledger} and {@code cash_float}, NOT from the
     * {@code RIDER_CREDIT} legs.</strong> The two record the same job earning — settlement writes
     * them in one transaction precisely so they cannot disagree — so adding both would pay the rider
     * twice on paper. The rider ledger is the right of the two here because it also carries tips,
     * cash-outs and work done for a delivery company, none of which is a settlement leg at all.
     */
    private Statement riderStatement(String ref, String name, StatementRange range, Ledger ledger) {
        List<RiderLedgerEntry> rows =
                riderLedger.between(ref, range.fromInstant(), range.toExclusive());

        // PLATFORM only. A carrier's rider earned the job and their COMPANY owes it; a cash tip is
        // already in their pocket. Both are real earnings and neither is the platform's debt, and
        // putting either in the net is how a platform pays for the same delivery twice.
        List<RiderLedgerEntry> payable = rows.stream()
                .filter(RiderLedgerEntry::isPayableByPlatform)
                .toList();

        BigDecimal earnings = sum(payable, EntryType.JOB_EARNING);
        BigDecimal tips = sum(payable, EntryType.TIP);
        BigDecimal reimbursed = sum(payable, EntryType.REIMBURSEMENT);
        BigDecimal adjustments = sum(payable, EntryType.ADJUSTMENT);
        // Held is negative and released is positive; CASHOUT_PAID is a zero row that exists only so
        // the history shows the payment. Their sum is what actually left the balance.
        BigDecimal cashOuts = sum(payable, EntryType.CASHOUT_HELD)
                .add(sum(payable, EntryType.CASHOUT_RELEASED))
                .add(sum(payable, EntryType.CASHOUT_PAID));

        // The rows, not just the total: they are what the itemisation is built from. Summed here
        // rather than queried twice so the figure on the statement and the rows underneath it are
        // the same data and cannot disagree.
        List<CashFloatEntry> collections = floatEntries.forHolderBetween(
                ref, CashFloatEntry.Kind.COLLECTED, range.fromInstant(), range.toExclusive());
        BigDecimal collected = collections.stream()
                .map(CashFloatEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal remitted = floatEntries.totalForHolderBetween(
                ref, CashFloatEntry.Kind.REMITTED, range.fromInstant(), range.toExclusive());

        long jobs = payable.stream().filter(e -> e.getEntryType() == EntryType.JOB_EARNING).count();

        List<Statement.Line> lines = new ArrayList<>();
        addIfAny(lines, Statement.Line.credit("Delivery earnings", earnings, jobs + " jobs"));
        addIfAny(lines, Statement.Line.credit("Tips", tips, null));
        addIfAny(lines, Statement.Line.credit("Expenses reimbursed", reimbursed,
                "money you fronted on errands"));
        // Signed both ways: an operator correction can go either direction and a line that could
        // only ever be a credit would quietly drop the ones that are not.
        addSigned(lines, "Adjustments", adjustments, null);
        addIfAny(lines, Statement.Line.debit("Cash paid out to you", cashOuts.negate(), null));
        addIfAny(lines, Statement.Line.debit("Cash collected from customers", collected,
                "the platform's money, taken at the door"));
        addIfAny(lines, Statement.Line.credit("Cash banked", remitted, null));

        // Computed from the rows rather than from the lines above, so it is a real check and not a
        // restatement. It fires if a new rider-ledger entry type is ever added without a line here:
        // the row would count towards the balance and appear nowhere on the statement.
        BigDecimal control = payable.stream()
                .map(RiderLedgerEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .add(remitted)
                .subtract(collected);

        return Statement.of(CounterpartyKind.RIDER, ref, name, range, currency,
                lines, control, riderEntries(payable, collections, range),
                // The order count is what they actually touched, not what they earned on. A rider
                // who collected on 44 orders and earned nothing was reported as "0 orders", which
                // is the same blank the itemisation used to be.
                Math.max((int) jobs, (int) collections.stream()
                        .map(CashFloatEntry::getOrderId)
                        .filter(java.util.Objects::nonNull)
                        .distinct()
                        .count()),
                riderNote(ref, rows, collected, remitted));
    }

    /**
     * One row per order the rider touched: what they took at the door, and what they kept.
     *
     * <p><strong>Both halves, and the cash half is the one that was missing.</strong> This used to
     * itemise {@code rider_ledger} job earnings alone, which is right on a platform where delivery
     * fees are set — and produces an EMPTY list on one where they are not, because a zero earning
     * is deliberately never written as a row. The live result was a rider told they owed the
     * platform two thousand four hundred dollars above an empty table. A number somebody is asked
     * to hand back is exactly the number that has to be checkable against the jobs that produced it.
     *
     * <p>So the two are merged by order id. {@code gross} is the cash taken at the door — the whole
     * basket, which is not theirs — and {@code net} is what they earned for the job. On a cash order
     * with no delivery fee that reads "you collected 24.00, you earned nothing", which is the true
     * and uncomfortable shape of the arrangement rather than a blank.
     */
    private List<Statement.Entry> riderEntries(List<RiderLedgerEntry> payable,
                                               List<CashFloatEntry> collections,
                                               StatementRange range) {
        // Order id -> what they earned on it. Orders with no earning simply never appear here.
        Map<UUID, RiderLedgerEntry> earnedBy = payable.stream()
                .filter(e -> e.getEntryType() == EntryType.JOB_EARNING && e.getOrderId() != null)
                .collect(Collectors.toMap(RiderLedgerEntry::getOrderId, e -> e, (a, b) -> a,
                        LinkedHashMap::new));

        Map<UUID, Statement.Entry> byOrder = new LinkedHashMap<>();

        // Cash first, in the order it was taken: on a cash platform this is most of the list.
        for (CashFloatEntry collection : collections) {
            UUID orderId = collection.getOrderId();
            if (orderId == null) {
                continue;
            }
            RiderLedgerEntry earned = earnedBy.get(orderId);
            // cash_float.created_at is insertable=false with a database default, so it is null on
            // any entity that has not been read back. Falling back to the earning's own timestamp
            // rather than letting that null reach the sort: an unflushed row must not be able to
            // take a rider's whole statement down with a NullPointerException.
            Instant at = collection.getCreatedAt() != null
                    ? collection.getCreatedAt()
                    : (earned != null ? earned.getEarnedAt() : range.fromInstant());
            byOrder.put(orderId, new Statement.Entry(
                    orderId,
                    at,
                    Statement.money(collection.getAmount()),
                    // A rider's earning is not commissioned: what the platform kept came off the
                    // delivery fee before the leg was written, and there is no per-job figure for
                    // it here that would not be an invention.
                    Statement.money(BigDecimal.ZERO),
                    Statement.money(earned == null ? BigDecimal.ZERO : earned.getAmount()),
                    "CASH"));
        }

        // Then any job they earned on without taking cash — a card order, or a carrier's fleet.
        for (RiderLedgerEntry earned : earnedBy.values()) {
            byOrder.computeIfAbsent(earned.getOrderId(), id -> new Statement.Entry(
                    id, earned.getEarnedAt(),
                    Statement.money(BigDecimal.ZERO),
                    Statement.money(BigDecimal.ZERO),
                    Statement.money(earned.getAmount()),
                    null));
        }

        return byOrder.values().stream()
                .sorted(Comparator.comparing(Statement.Entry::at))
                .limit(MAX_ENTRIES)
                .toList();
    }

    /**
     * What the rider's figures cannot say on their own.
     *
     * <p>Work a delivery company owes them, cash they took in an earlier period and still hold, and
     * cash tips already in their pocket. All three are money the rider genuinely has coming or
     * genuinely has, and all three are excluded from the net — so leaving them unsaid is how a
     * statement can be arithmetically perfect and still read as short-paying somebody.
     */
    private String riderNote(String ref, List<RiderLedgerEntry> rows, BigDecimal collected,
                             BigDecimal remitted) {
        List<String> notes = new ArrayList<>();

        BigDecimal carrierOwed = rows.stream()
                .filter(e -> e.getPayableBy() == PayableBy.CARRIER)
                .map(RiderLedgerEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (carrierOwed.signum() != 0) {
            notes.add("You also earned " + Statement.money(carrierOwed) + " " + currency
                    + " on jobs for a delivery company in this period. That is your company's to "
                    + "pay, not the platform's, so it is not in the total above.");
        }

        BigDecimal inHand = rows.stream()
                .filter(e -> e.getPayableBy() == PayableBy.IN_HAND)
                .map(RiderLedgerEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (inHand.signum() != 0) {
            notes.add("Cash tips of " + Statement.money(inHand) + " " + currency
                    + " were handed to you directly and are not paid again here.");
        }

        BigDecimal stillHeld = floatEntries.outstandingTotalFor(ref);
        if (stillHeld != null && stillHeld.signum() != 0
                && stillHeld.compareTo(collected.subtract(remitted)) != 0) {
            // Deliberately outside the range: cash taken in July and still not banked in August is a
            // fact about today that no August window can show, and it is the number an operator
            // chasing a float actually wants.
            notes.add("You are currently holding " + Statement.money(stillHeld) + " " + currency
                    + " of platform cash in total, including anything collected before this period.");
        }

        return notes.isEmpty() ? null : String.join(" ", notes);
    }

    // ------------------------------------------------------------------------------- platform

    /**
     * The platform's own position: what it earned, what it gave away, and what is still in pockets.
     *
     * <p>The sign convention is unchanged and reads correctly here without a special case:
     * commission is money owed TO the platform, so it is a DEBIT, and the statement comes out
     * {@code THEY_OWE}. Everybody else owes the platform its cut — which, on a cash platform, is
     * literally true and is exactly what the note is about.
     *
     * <p><strong>Outstanding cash is stated and deliberately not added.</strong> The commission on a
     * cash order is INSIDE the notes a rider is still carrying: the same money, described twice.
     * Adding both would overstate what the platform is owed by the whole of its own commission on
     * every unbanked order, which is the sort of double count that looks like growth.
     */
    private Statement platformStatement(String ref, String name, StatementRange range,
                                        Ledger ledger) {
        BigDecimal commission = ledger.sumOf(Leg.PLATFORM_COMMISSION);
        BigDecimal subsidy = ledger.sumOf(Leg.PLATFORM_SUBSIDY);

        List<Statement.Line> lines = new ArrayList<>();
        addIfAny(lines, Statement.Line.debit("Commission earned", commission,
                ledger.orderCount() + " orders"));
        addIfAny(lines, Statement.Line.credit("Subsidies paid", subsidy,
                "free delivery and promotions the platform absorbed"));

        BigDecimal control = subsidy.subtract(commission);

        List<Statement.Entry> entries = ledger.own().stream()
                .filter(t -> t.getLeg() == Leg.PLATFORM_COMMISSION
                        || t.getLeg() == Leg.PLATFORM_SUBSIDY)
                .limit(MAX_ENTRIES)
                .map(t -> {
                    BigDecimal kept = t.getLeg() == Leg.PLATFORM_COMMISSION
                            ? t.getAmount() : t.getAmount().negate();
                    return new Statement.Entry(t.getOrderId(), t.getCreatedAt(),
                            Statement.money(ledger.collectedOn(t.getOrderId())),
                            Statement.money(kept), Statement.money(kept),
                            ledger.paymentMethodOn(t.getOrderId()));
                })
                .toList();

        return Statement.of(CounterpartyKind.PLATFORM, ref, name, range, currency,
                lines, control, entries, ledger.orderCount(),
                platformNote(range, ledger));
    }

    private String platformNote(StatementRange range, Ledger ledger) {
        BigDecimal collected = floatEntries.totalBetween(
                CashFloatEntry.Kind.COLLECTED, range.fromInstant(), range.toExclusive());
        BigDecimal banked = floatEntries.totalBetween(
                CashFloatEntry.Kind.REMITTED, range.fromInstant(), range.toExclusive());
        BigDecimal outstanding = floatEntries.outstandingTotal();

        List<String> notes = new ArrayList<>();
        notes.add("Riders collected " + Statement.money(collected) + " " + currency
                + " in cash in this period and banked " + Statement.money(banked)
                + "; " + Statement.money(outstanding)
                + " is still held across all holders. That cash already contains the commission "
                + "above, so it is reported here rather than added to the total, which would count "
                + "the same money twice.");
        if (ledger.truncated()) {
            notes.add(truncationNote(ledger));
        }
        return String.join(" ", notes);
    }

    // ---------------------------------------------------------------------- shared arithmetic

    /**
     * Turns a net into a gross line and a commission line, where the ledger can prove the split.
     *
     * <p>Always exactly two lines that sum to the net, or one line that IS the net. The gross is
     * derived by ADDING the commission to the net rather than being read from anywhere, so the two
     * lines cannot fail to add up however odd the underlying order was.
     */
    private List<Statement.Line> grossUp(String grossLabel, BigDecimal owed, Attribution take,
                                         String grossNote) {
        BigDecimal kept = take.amount();
        if (kept.signum() == 0) {
            // No line at all when there is nothing to report. A zero line reads as a claim that
            // something happened and came to nothing, which is a different statement from silence,
            // and omitting it cannot change the net.
            return owed.signum() == 0
                    ? List.of()
                    : List.of(Statement.Line.credit(grossLabel, owed, grossNote));
        }
        if (kept.signum() > 0) {
            return List.of(
                    Statement.Line.credit(grossLabel, owed.add(kept), grossNote),
                    Statement.Line.debit(commissionLabel(), kept, null));
        }
        // The platform paid INTO these orders rather than taking out of them — a free delivery or a
        // promo code costing more than the commission it earned. Shown as what it is rather than as
        // a negative commission, for the same reason PLATFORM_SUBSIDY is its own leg: a figure whose
        // meaning depends on reading its sign is one that gets read wrong.
        return List.of(
                Statement.Line.credit(grossLabel, owed.add(kept), grossNote),
                Statement.Line.credit("Platform contribution", kept.negate(),
                        "promotions the platform absorbed on these orders"));
    }

    /** "Platform commission (12.5%)", with the rate rendered as it is configured. */
    private String commissionLabel() {
        return "Platform commission (" + commissionPercentage.stripTrailingZeros().toPlainString()
                + "%)";
    }

    /**
     * The statement's note: what the figures could not say.
     *
     * <p>Two things, and both matter. First, whether the breakdown is provable — on an order with
     * more than one payee the platform's leg is a residue that nothing separates, so no commission
     * line is shown for it and the reader is told rather than left to wonder why the column is
     * short. Second, that the net is exact either way, because that is the number they care about.
     */
    private String note(StatementRange range, Ledger ledger, Attribution take, String subject) {
        List<String> notes = new ArrayList<>();
        if (take.unprovable() > 0) {
            notes.add("On " + take.unprovable() + " of these orders the platform's share cannot be "
                    + "split between " + subject + " and delivery, because the ledger records it as "
                    + "one residual figure for the whole order. Those orders contribute to the total "
                    + "below but not to the commission line, which is therefore lower than the "
                    + "commission actually charged. The total owed is exact.");
        } else if (take.amount().signum() > 0) {
            notes.add("The commission line is what the platform actually retained on these orders, "
                    + "read from the ledger rather than recalculated from a rate.");
        }
        if (ledger.truncated()) {
            notes.add(truncationNote(ledger));
        }
        return notes.isEmpty() ? null : String.join(" ", notes);
    }

    private String truncationNote(Ledger ledger) {
        return "The totals cover all " + ledger.orderCount()
                + " orders in this period; only the first " + MAX_ENTRIES + " are itemised.";
    }

    private static void addIfAny(List<Statement.Line> lines, Statement.Line line) {
        // A zero line is noise on a statement and, worse, reads as a claim that something happened
        // and came to nothing. Omitting it cannot change the net.
        if (line.amount().signum() != 0) {
            lines.add(line);
        }
    }

    private static void addSigned(List<Statement.Line> lines, String label, BigDecimal amount,
                                  String note) {
        if (amount.signum() > 0) {
            lines.add(Statement.Line.credit(label, amount, note));
        } else if (amount.signum() < 0) {
            lines.add(Statement.Line.debit(label, amount.negate(), note));
        }
    }

    private static BigDecimal sum(List<RiderLedgerEntry> rows, EntryType type) {
        return rows.stream()
                .filter(e -> e.getEntryType() == type)
                .map(RiderLedgerEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    // ---------------------------------------------------------------------- counterparty list

    /** One row of the counterparties listing. */
    public record Summary(CounterpartyKind kind, String ref, String name, BigDecimal net,
                          Statement.Direction direction, int orders, String recipient,
                          Instant lastSentAt) {
    }

    /**
     * The money that belongs to nobody.
     *
     * <p>Every leg written before attribution shipped, plus any later one whose event named no
     * party. It is reported beside the counterparties rather than quietly excluded, because a
     * listing that showed two shops and 300 dollars while the ledger held 2,400 would be read as the
     * platform having done very little business — and the number that is missing is the whole point
     * of the change that produced this API.
     */
    public record Unattributed(BigDecimal amount, long orders, String note) {
    }

    /** The counterparties listing: everyone with activity, plus what could not be assigned. */
    public record Counterparties(StatementRange range, String currency, List<Summary> counterparties,
                                 Unattributed unattributed) {
    }

    @Transactional(readOnly = true)
    public Counterparties list(StatementRange range) {
        List<Object[]> active =
                transactions.activeCounterparties(range.fromInstant(), range.toExclusive());

        if (active.size() > MAX_COUNTERPARTIES) {
            log.warn("{} counterparties have activity between {} and {}; listing the first {}",
                    active.size(), range.from(), range.to(), MAX_COUNTERPARTIES);
        }

        List<Summary> rows = new ArrayList<>();
        Set<String> refs = new LinkedHashSet<>();
        List<Object[]> capped = active.size() > MAX_COUNTERPARTIES
                ? active.subList(0, MAX_COUNTERPARTIES)
                : active;

        for (Object[] row : capped) {
            CounterpartyKind kind = (CounterpartyKind) row[0];
            String ref = (String) row[1];
            refs.add(ref);
            Statement statement = build(kind, ref, range);
            rows.add(new Summary(kind, ref, statement.name(), statement.net().amount(),
                    statement.net().direction(), statement.orders(),
                    directory.recipientOf(kind, ref), null));
        }

        // One query for every party's last send rather than one per row. The listing is the screen
        // an operator works a month-end from, and a query per shop is how it becomes the slow screen
        // nobody opens.
        Map<String, Instant> lastSent = lastSentFor(refs);
        List<Summary> withDispatch = rows.stream()
                .map(r -> new Summary(r.kind(), r.ref(), r.name(), r.net(), r.direction(),
                        r.orders(), r.recipient(), lastSent.get(dispatchKey(r.kind(), r.ref()))))
                // Largest amount first, whichever way it points. This is a work list, and the row
                // worth an operator's attention is the big one — a rider holding 400 of the
                // platform's cash matters as much as a shop owed 400, and sorting them into
                // separate halves would bury one of the two.
                .sorted(Comparator.comparing(Summary::net).reversed())
                .toList();

        return new Counterparties(range, currency, withDispatch, unattributed(range));
    }

    private Map<String, Instant> lastSentFor(Set<String> refs) {
        if (refs.isEmpty()) {
            return Map.of();
        }
        Map<String, Instant> lastSent = new HashMap<>();
        for (StatementDispatch dispatch : dispatches.recentFor(refs)) {
            // Newest first out of the query, so the first one seen for a party is the latest.
            lastSent.putIfAbsent(
                    dispatchKey(dispatch.getCounterpartyKind(), dispatch.getCounterpartyRef()),
                    dispatch.getSentAt());
        }
        return lastSent;
    }

    /** Keyed on both halves: a provider id and a Keycloak subject could in principle collide. */
    private static String dispatchKey(CounterpartyKind kind, String ref) {
        return kind + " " + ref;
    }

    private Unattributed unattributed(StatementRange range) {
        List<Object[]> result = transactions.unattributedTotal(
                AccountingTransactionRepository.PAYEE_LEGS,
                range.fromInstant(), range.toExclusive());

        BigDecimal amount = BigDecimal.ZERO;
        long orders = 0;
        if (!result.isEmpty() && result.get(0) != null) {
            Object[] row = result.get(0);
            amount = row[0] == null ? BigDecimal.ZERO : (BigDecimal) row[0];
            orders = row[1] == null ? 0 : ((Number) row[1]).longValue();
        }

        String note = orders == 0
                ? "Every payout in this period is attributed to a counterparty."
                : orders + " orders paying " + Statement.money(amount) + " " + currency
                        + " cannot be assigned to a counterparty. They were settled before the "
                        + "ledger recorded who each leg was for, and the identity survives only in "
                        + "Order Manager's schema, which this service cannot read. The figure is "
                        + "closed: it can only shrink as those orders age out of the range asked "
                        + "for, and no new order joins it.";

        return new Unattributed(Statement.money(amount), orders, note);
    }

    // --------------------------------------------------------------------------- ledger access

    /**
     * The legs a statement is built from: this party's own, plus the rest of each order's.
     *
     * <p>Both halves are needed and the second is the less obvious one. What the platform kept on an
     * order is on the PLATFORM's leg, so a merchant statement built only from legs the merchant can
     * see would have a net and no commission line at all. Fetched for the whole order set in one
     * query rather than per order.
     */
    private Ledger ledgerFor(CounterpartyKind kind, String ref, StatementRange range) {
        List<AccountingTransaction> own = transactions.legsForCounterparty(
                kind, ref, range.fromInstant(), range.toExclusive());

        Set<UUID> orderIds = own.stream()
                .map(AccountingTransaction::getOrderId)
                .collect(java.util.stream.Collectors.toCollection(LinkedHashSet::new));

        Map<UUID, List<AccountingTransaction>> byOrder = orderIds.isEmpty()
                ? Map.of()
                : transactions.findByOrderIdIn(orderIds).stream()
                        .collect(java.util.stream.Collectors.groupingBy(
                                AccountingTransaction::getOrderId,
                                LinkedHashMap::new,
                                java.util.stream.Collectors.toList()));

        return new Ledger(own, byOrder, orderIds);
    }

    /**
     * How much of the platform's take this statement is allowed to claim, and how much it is not.
     *
     * @param amount     the part that is provably about this counterparty alone
     * @param unprovable how many orders had to be left out of it, so the note can say so
     */
    private record Attribution(BigDecimal amount, int unprovable) {
    }

    /** The legs behind one statement, with the questions a statement asks of them. */
    private record Ledger(List<AccountingTransaction> own,
                          Map<UUID, List<AccountingTransaction>> byOrder,
                          Set<UUID> orderIds) {

        BigDecimal sumOf(Leg leg) {
            return own.stream()
                    .filter(t -> t.getLeg() == leg)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
        }

        int orderCount() {
            return orderIds.size();
        }

        boolean truncated() {
            return orderIds.size() > MAX_ENTRIES;
        }

        Set<UUID> orderIdsWith(Leg leg) {
            Set<UUID> ids = new HashSet<>();
            for (AccountingTransaction t : own) {
                if (t.getLeg() == leg) {
                    ids.add(t.getOrderId());
                }
            }
            return ids;
        }

        /**
         * What the platform kept on the orders where THIS party is the only one it could be about.
         *
         * <p>The platform's leg is a residue — everything the customer paid that nobody else
         * received — so on an order with a shop and a delivery company it is the goods commission
         * and the delivery cut added together, and there is nothing in the ledger that separates
         * them. Guessing a split would put an invented number on a statement somebody is going to
         * check. So the residue is claimed only where there is exactly one non-platform payee, and
         * the orders where it is not are counted so the note can admit it.
         *
         * <p>An unattributed payee leg on the order counts AS a second payee. It might be this same
         * party, but "might" is not a basis for putting a figure on a statement.
         */
        Attribution platformTake(CounterpartyKind kind, String ref) {
            BigDecimal claimed = BigDecimal.ZERO;
            int unprovable = 0;

            for (UUID orderId : orderIds) {
                List<AccountingTransaction> legs = byOrder.getOrDefault(orderId, List.of());
                if (solePayee(legs, kind, ref)) {
                    claimed = claimed.add(keptOn(legs));
                } else if (keptOn(legs).signum() != 0) {
                    unprovable++;
                }
            }
            return new Attribution(claimed, unprovable);
        }

        private static boolean solePayee(List<AccountingTransaction> legs, CounterpartyKind kind,
                                         String ref) {
            boolean foundSelf = false;
            for (AccountingTransaction leg : legs) {
                if (!AccountingTransactionRepository.PAYEE_LEGS.contains(leg.getLeg())) {
                    continue;
                }
                if (leg.getCounterpartyKind() == kind && ref.equals(leg.getCounterpartyRef())) {
                    foundSelf = true;
                    continue;
                }
                // Somebody else was paid on this order — or somebody unidentified was, which is the
                // same answer for this purpose.
                return false;
            }
            return foundSelf;
        }

        /** Commission less subsidy: what the platform actually kept on one order, signed. */
        private static BigDecimal keptOn(List<AccountingTransaction> legs) {
            BigDecimal kept = BigDecimal.ZERO;
            for (AccountingTransaction leg : legs) {
                if (leg.getLeg() == Leg.PLATFORM_COMMISSION) {
                    kept = kept.add(leg.getAmount());
                } else if (leg.getLeg() == Leg.PLATFORM_SUBSIDY) {
                    kept = kept.subtract(leg.getAmount());
                }
            }
            return kept;
        }

        /** What the customer paid for one order, whichever way they paid it. */
        BigDecimal collectedOn(UUID orderId) {
            return byOrder.getOrDefault(orderId, List.of()).stream()
                    .filter(t -> t.getLeg() == Leg.CASH_COLLECTED || t.getLeg() == Leg.CUSTOMER_DEBIT)
                    .map(AccountingTransaction::getAmount)
                    .findFirst()
                    .orElse(BigDecimal.ZERO);
        }

        /**
         * How the order was paid for, read off the collection leg.
         *
         * <p>Not a stored field and deliberately not one: the two legs already encode it, and a
         * third place saying the same thing is a third place to get it wrong.
         */
        String paymentMethodOn(UUID orderId) {
            for (AccountingTransaction leg : byOrder.getOrDefault(orderId, List.of())) {
                if (leg.getLeg() == Leg.CASH_COLLECTED) {
                    return "CASH";
                }
                if (leg.getLeg() == Leg.CUSTOMER_DEBIT) {
                    return "CARD";
                }
            }
            return null;
        }

        /**
         * One row per order, showing what it was worth and what the platform kept.
         *
         * <p>The commission on a row is only filled in where it is provable for the whole statement;
         * where it is not, it is zero and the gross equals the net. Filling it with an
         * order-by-order guess would make the itemised rows disagree with the totals above them.
         */
        List<Statement.Entry> entriesFor(Leg leg, Attribution take) {
            boolean provable = take.unprovable() == 0;
            List<Statement.Entry> entries = new ArrayList<>();
            for (AccountingTransaction t : own) {
                if (t.getLeg() != leg) {
                    continue;
                }
                if (entries.size() >= MAX_ENTRIES) {
                    break;
                }
                List<AccountingTransaction> legs = byOrder.getOrDefault(t.getOrderId(), List.of());
                BigDecimal kept = provable ? keptOn(legs) : BigDecimal.ZERO;
                entries.add(new Statement.Entry(
                        t.getOrderId(), t.getCreatedAt(),
                        Statement.money(t.getAmount().add(kept)),
                        Statement.money(kept),
                        Statement.money(t.getAmount()),
                        paymentMethodOn(t.getOrderId())));
            }
            return entries;
        }
    }

    /** The last statement sent to one party, for the send endpoint's duplicate check. */
    @Transactional(readOnly = true)
    public Optional<StatementDispatch> lastSentTo(CounterpartyKind kind, String ref) {
        return dispatches.findFirstByCounterpartyKindAndCounterpartyRefOrderBySentAtDesc(kind, ref);
    }
}
