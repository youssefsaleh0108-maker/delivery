package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.EntryType;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.payout.RiderPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * A rider's own money: what they earned, what they were tipped, and what they can take out.
 *
 * <p>The earning rows themselves are written by {@link SettlementService}, in the same transaction
 * as the ledger legs they mirror — see the note there for why they are not deferred. This class
 * owns everything that happens afterwards: tips, the balance, the statement the Earnings screen
 * renders, and the cash-out state machine.
 *
 * <p><strong>Two numbers, and they are not the same number.</strong> What a rider EARNED includes a
 * cash tip already in their pocket and a job a delivery company will pay them for. What the
 * platform OWES them is only the rows marked {@code PLATFORM}, less any cash they are still
 * carrying on the platform's behalf. Showing one figure where the app needs both is how a rider
 * comes to believe the platform is short-paying them.
 */
@Service
public class RiderEarningsService {

    private static final Logger log = LoggerFactory.getLogger(RiderEarningsService.class);

    /** How much free text is kept from a rider or a customer. Longer than any real instruction. */
    private static final int MAX_NOTE = 500;

    private final RiderLedgerRepository ledger;
    private final RiderCashOutRepository cashOuts;
    private final CashFloatRepository floatEntries;
    private final RiderPayoutProviders payoutProviders;
    private final BigDecimal minimumCashOut;
    private final BigDecimal maximumTip;
    private final boolean offsetCashFloat;
    private final ZoneId defaultZone;
    private final String currency;

    public RiderEarningsService(RiderLedgerRepository ledger,
                                RiderCashOutRepository cashOuts,
                                CashFloatRepository floatEntries,
                                RiderPayoutProviders payoutProviders,
                                // Below this a cash-out is refused. Nothing here pays automatically
                                // — an operator does — so a queue of 40-cent requests costs more in
                                // their time than the requests are worth.
                                @Value("${delivery.rider-earnings.minimum-cash-out:5.00}")
                                BigDecimal minimumCashOut,
                                // A ceiling on a single tip. Not a policy about generosity: it is
                                // the fat-finger guard, because the amount arrives from a phone
                                // keypad and a misplaced decimal point is the common case.
                                @Value("${delivery.rider-earnings.maximum-tip:100.00}")
                                BigDecimal maximumTip,
                                // Whether cash a rider is still carrying reduces what they can take
                                // out. See availableFor() — the default is on, and turning it off
                                // means the platform will hand a rider money while they are holding
                                // more of the platform's.
                                @Value("${delivery.rider-earnings.offset-cash-float:true}")
                                boolean offsetCashFloat,
                                // "Today" is a local-calendar question and the platform operates in
                                // one region. UTC is the safe default rather than the right one:
                                // see statement(), which takes a zone per request.
                                @Value("${delivery.rider-earnings.zone:UTC}") String zone,
                                @Value("${delivery.accounting.currency:USD}") String currency) {
        this.ledger = ledger;
        this.cashOuts = cashOuts;
        this.floatEntries = floatEntries;
        this.payoutProviders = payoutProviders;
        this.minimumCashOut = minimumCashOut;
        this.maximumTip = maximumTip;
        this.offsetCashFloat = offsetCashFloat;
        this.defaultZone = ZoneId.of(zone);
        this.currency = currency;
    }

    public ZoneId defaultZone() {
        return defaultZone;
    }

    public String currency() {
        return currency;
    }

    // ------------------------------------------------------------------------------------ tips

    /**
     * A customer tipping the rider who delivered their order.
     *
     * <p><strong>A tip is not revenue and is never commissioned.</strong> That is the entire reason
     * it is a row here and not an amount added to the order. Commission is computed in
     * {@link SettlementService} from the order total, which was fixed when the order was priced; a
     * tip arrives afterwards, belongs to the rider outright, and the settlement arithmetic never
     * sees it. There is no code path that could take a percentage of it, which is a stronger
     * guarantee than a rule saying not to.
     *
     * <p>It belongs to the RIDER even when a company employs them. The customer tipped the person
     * who turned up, not their employer, and routing it through the company would be the platform
     * giving away somebody else's money.
     *
     * <p><strong>Who is allowed to tip.</strong> The job earning written at delivery carries the
     * customer who paid, and that is what {@code tippedBy} is checked against. Authorising on the
     * CUSTOMER role alone would let anybody tip anybody's order — harmless-looking today, and the
     * wrong card charged the moment an online tip is real.
     *
     * @param method how the money reached the rider. See {@link TipMethod}
     * @return the row written
     * @throws IllegalArgumentException the order has no delivered job, the amount is out of range,
     *                                  or the caller did not pay for this order
     * @throws IllegalStateException    this order has already been tipped
     */
    @Transactional
    public RiderLedgerEntry tip(UUID orderId, String tippedBy, BigDecimal amount,
                                TipMethod method) {

        RiderLedgerEntry job = ledger.findFirstByOrderIdAndEntryType(orderId, EntryType.JOB_EARNING)
                .orElseThrow(() -> new IllegalArgumentException(
                        "That order has no delivered job to tip"));

        // Compared, never echoed. Telling a caller whose order it actually is would turn this
        // endpoint into a way of asking who bought what.
        if (job.getCustomerRef() == null || !job.getCustomerRef().equals(tippedBy)) {
            throw new IllegalArgumentException("That order has no delivered job to tip");
        }

        BigDecimal tip = amount == null ? null : amount.setScale(2, RoundingMode.HALF_UP);
        if (tip == null || tip.signum() <= 0) {
            throw new IllegalArgumentException("A tip has to be more than nothing");
        }
        if (tip.compareTo(maximumTip) > 0) {
            throw new IllegalArgumentException(
                    "The most you can tip in one go is " + maximumTip + " " + currency);
        }

        // ONLINE means the platform took the money and now owes it to the rider. Nothing in this
        // platform can take money from a customer — there is no payment processor integrated, which
        // is the same admission SettlementService.SettlementMode makes about the bank — so
        // accepting one here would credit a rider a balance nobody ever collected, and the platform
        // would pay real money out against it. Refused until a processor exists.
        if (method == TipMethod.ONLINE) {
            throw new IllegalStateException(
                    "Online tips need a payment processor and none is configured. "
                            + "A tip handed over at the door can be recorded as CASH.");
        }

        RiderLedgerEntry entry = RiderLedgerEntry.tip(
                job.getRiderRef(), orderId, tip, currency, job.getFleet(), job.getCarrierRef(),
                method == TipMethod.CASH, Instant.now());

        try {
            ledger.saveAndFlush(entry);
        } catch (DataIntegrityViolationException e) {
            // One tip per order, enforced by the unique index rather than by a read first: two taps
            // on a phone are the ordinary case and a check-then-act would let both through.
            throw new IllegalStateException("That order has already been tipped");
        }

        log.info("Order {} tipped {} {} to rider {} ({})",
                orderId, tip, currency, job.getRiderRef(), method);
        return entry;
    }

    /** How a tip reached the rider, which decides whether the platform owes it. */
    public enum TipMethod {
        /**
         * Notes handed over at the door. The rider already has it.
         *
         * <p>Recorded so it shows in what they earned, and deliberately excluded from the balance:
         * the platform never held this money, and offering to pay it out would pay it twice.
         */
        CASH,
        /**
         * Charged to the customer, held by the platform, owed to the rider.
         *
         * <p>Modelled, and refused at the door until there is something that can actually charge a
         * customer. See {@link #tip}.
         */
        ONLINE
    }

    // --------------------------------------------------------------------------------- balances

    /** What the platform owes this rider before anything is netted off. */
    @Transactional(readOnly = true)
    public BigDecimal balanceOf(String riderRef) {
        return scale(ledger.balanceOf(riderRef));
    }

    /**
     * What the rider can actually ask for.
     *
     * <p><strong>Cash they are still carrying is netted off, and this is not an optional nicety.
     * </strong> On a cash order the rider takes the whole total at the door and owes it to the
     * platform until they bank it; the platform separately owes them their share of the fee. Paying
     * out the second while the first is outstanding hands money to somebody who is already holding
     * more of the platform's — and on a cash Butler errand it is worse than that, because the rider
     * collected their own reimbursement at the door too, and the net position is the rider owing
     * the platform its commission.
     *
     * <p>The result can therefore be NEGATIVE, and is returned that way rather than clamped. A
     * rider who owes the platform money should see that they do; a zero would look like having
     * earned nothing, which is a different and more alarming statement.
     */
    @Transactional(readOnly = true)
    public BigDecimal availableFor(String riderRef) {
        BigDecimal balance = balanceOf(riderRef);
        if (!offsetCashFloat) {
            return balance;
        }
        return scale(balance.subtract(floatEntries.outstandingTotalFor(riderRef)));
    }

    // -------------------------------------------------------------------------------- statement

    /** One day of a rider's work, in their own calendar. */
    public record DayTotal(LocalDate day, BigDecimal earnings, BigDecimal tips, BigDecimal total,
                           int jobs) {
    }

    /**
     * What the Earnings screen renders: today, this week, and a day-by-day series.
     *
     * <p><strong>Totalled in Java rather than grouped in SQL, on purpose.</strong> Which day a
     * delivery at 23:40 UTC belongs to depends on the rider's calendar, and a native
     * {@code date_trunc(... AT TIME ZONE ...)} would put that rule in a second place — one that no
     * test without a database can reach. A single rider's fortnight is at most a few hundred rows,
     * so there is nothing to win by pushing it down and a real correctness rule to lose.
     *
     * <p>Everything buckets on {@code earnedAt}, which is when the order was delivered, not when
     * the row was written. The bus is at-least-once and can be slow; an event that arrives an hour
     * late must still land in the day the rider worked, or their Monday total changes on Tuesday.
     *
     * @param days how many days back the series runs, including today
     */
    @Transactional(readOnly = true)
    public Statement statement(String riderRef, ZoneId zone, int days) {
        LocalDate today = LocalDate.now(zone);
        LocalDate seriesFrom = today.minusDays(Math.max(days, 1) - 1L);
        // The ISO week, which starts on Monday.
        LocalDate weekStart = today.with(DayOfWeek.MONDAY);

        // The rows fetched cover BOTH the series and the week, whichever reaches further back. A
        // 3-day series requested on a Thursday would otherwise compute "this week" from Tuesday
        // onwards and quietly under-report it — a total that is wrong by an amount that depends on
        // the day of the week is the kind nobody reproduces.
        LocalDate from = seriesFrom.isBefore(weekStart) ? seriesFrom : weekStart;

        Instant windowStart = from.atStartOfDay(zone).toInstant();
        Instant windowEnd = today.plusDays(1).atStartOfDay(zone).toInstant();

        List<RiderLedgerEntry> rows = ledger.between(riderRef, windowStart, windowEnd);

        // Every day in the window, including the ones with no work. A series with gaps in it draws
        // a chart that lies about which days the rider was out.
        Map<LocalDate, Bucket> buckets = new LinkedHashMap<>();
        for (LocalDate day = from; !day.isAfter(today); day = day.plusDays(1)) {
            buckets.put(day, new Bucket());
        }

        for (RiderLedgerEntry row : rows) {
            if (!row.isEarning()) {
                // A hold, a release or a payout moves the balance, not what was earned. Counting a
                // cash-out as a day's earnings would show the rider's Tuesday going negative
                // because they took their own money out on it.
                continue;
            }
            Bucket bucket = buckets.get(LocalDate.ofInstant(row.getEarnedAt(), zone));
            if (bucket == null) {
                continue;
            }
            bucket.add(row);
        }

        List<DayTotal> all = buckets.entrySet().stream()
                .map(e -> e.getValue().toTotal(e.getKey()))
                .toList();

        // The series the caller asked for, which may be shorter than what was fetched for the week.
        List<DayTotal> series = all.stream()
                .filter(d -> !d.day().isBefore(seriesFrom))
                .toList();

        return new Statement(
                totalOf(all, d -> d.day().equals(today)),
                totalOf(all, d -> !d.day().isBefore(weekStart)),
                series);
    }

    /** Today, this week, and the day-by-day series behind them. */
    public record Statement(Total today, Total thisWeek, List<DayTotal> series) {
    }

    /**
     * A period's totals.
     *
     * <p>Earnings and tips are separate all the way to the screen and only added at the end. A
     * rider judging whether a shift was worth doing needs to know how much of it was the platform
     * paying and how much was people being kind, and a single figure hides exactly that.
     */
    public record Total(BigDecimal earnings, BigDecimal tips, BigDecimal total, int jobs) {
    }

    private static Total totalOf(List<DayTotal> series,
                                 java.util.function.Predicate<DayTotal> include) {
        BigDecimal earnings = BigDecimal.ZERO;
        BigDecimal tips = BigDecimal.ZERO;
        int jobs = 0;
        for (DayTotal d : series) {
            if (!include.test(d)) {
                continue;
            }
            earnings = earnings.add(d.earnings());
            tips = tips.add(d.tips());
            jobs += d.jobs();
        }
        return new Total(scale(earnings), scale(tips), scale(earnings.add(tips)), jobs);
    }

    /** Accumulates one day. Mutable and package-private to this file only. */
    private static final class Bucket {
        private BigDecimal earnings = BigDecimal.ZERO;
        private BigDecimal tips = BigDecimal.ZERO;
        private int jobs;

        void add(RiderLedgerEntry row) {
            if (row.getEntryType() == EntryType.TIP) {
                tips = tips.add(row.getAmount());
            } else {
                earnings = earnings.add(row.getAmount());
                jobs++;
            }
        }

        DayTotal toTotal(LocalDate day) {
            return new DayTotal(day, scale(earnings), scale(tips), scale(earnings.add(tips)), jobs);
        }
    }

    /**
     * The recent jobs, each with the tip it attracted.
     *
     * <p>Joined here rather than left to the client. The rider's question is "what did that drop
     * pay me", and an app that had to correlate two lists to answer it would eventually correlate
     * them wrongly.
     */
    @Transactional(readOnly = true)
    public List<Job> recentJobs(String riderRef, int limit) {
        List<RiderLedgerEntry> jobs = ledger.findByRiderRefAndEntryTypeOrderByEarnedAtDesc(
                riderRef, EntryType.JOB_EARNING, PageRequest.of(0, limit));
        if (jobs.isEmpty()) {
            return List.of();
        }

        // One query for every sibling row of every job on the page, rather than one per job. The
        // list is short, but a per-row query in a list endpoint is the shape that stops being
        // short later without anybody noticing.
        List<UUID> orderIds = jobs.stream().map(RiderLedgerEntry::getOrderId).toList();
        Map<UUID, BigDecimal> tips = new java.util.HashMap<>();
        Map<UUID, BigDecimal> reimbursements = new java.util.HashMap<>();
        for (RiderLedgerEntry row : ledger.findByRiderRefAndOrderIdIn(riderRef, orderIds)) {
            if (row.getEntryType() == EntryType.TIP) {
                tips.merge(row.getOrderId(), row.getAmount(), BigDecimal::add);
            } else if (row.getEntryType() == EntryType.REIMBURSEMENT) {
                reimbursements.merge(row.getOrderId(), row.getAmount(), BigDecimal::add);
            }
        }

        List<Job> result = new ArrayList<>(jobs.size());
        for (RiderLedgerEntry job : jobs) {
            result.add(new Job(job.getOrderId(), scale(job.getAmount()),
                    scale(tips.get(job.getOrderId())),
                    scale(reimbursements.get(job.getOrderId())),
                    job.getFleet(), job.getPayableBy(), job.getEarnedAt()));
        }
        return result;
    }

    /**
     * One job on the rider's list.
     *
     * <p>{@code payableBy} is on the payload rather than implied, so the app can say "your company
     * pays this" instead of showing the rider a number the platform has no intention of handing
     * over. That distinction is invisible in the amount and unforgivable to get wrong on screen.
     */
    public record Job(UUID orderId, BigDecimal earned, BigDecimal tip, BigDecimal reimbursement,
                      RiderLedgerEntry.Fleet fleet, RiderLedgerEntry.PayableBy payableBy,
                      Instant deliveredAt) {
    }

    // --------------------------------------------------------------------------------- cash-out

    /**
     * A rider asking for their balance in money.
     *
     * <p><strong>How this is made safe under concurrency, which is the whole design of it.</strong>
     * The obvious implementation reads the balance, compares, and writes a hold — a check-then-act
     * with a window in the middle that two simultaneous taps of the same button walk straight
     * through, and the platform pays out twice. Three things close it, in this order:
     *
     * <ol>
     *   <li>The request row is inserted and FLUSHED before the hold is written. A unique partial
     *       index on {@code (rider_ref) WHERE status = 'REQUESTED'} means the second transaction
     *       blocks on that insert until the first commits, and then fails outright. It never
     *       reaches the hold.</li>
     *   <li>The hold is written in the same transaction as the request, so a request that exists
     *       always has a hold behind it and a balance can never show money that has been asked for.
     *       </li>
     *   <li>The balance is only ever read INSIDE that transaction, after the serialisation point.
     *       </li>
     * </ol>
     *
     * <p>The database is the thing that enforces it, deliberately — not a lock, not a
     * {@code SELECT FOR UPDATE} on a balance that exists as no single row, and not serializable
     * isolation applied to the whole service. Making the overdraw IMPOSSIBLE beats making it
     * unlikely. Concurrent CREDITS are safe without any of this because they only ever increase
     * what is available.
     *
     * @throws IllegalArgumentException the amount is below the minimum, or above what is available
     * @throws IllegalStateException    the rider already has a cash-out waiting
     */
    @Transactional
    public RiderCashOut requestCashOut(String riderRef, BigDecimal amount, String payoutNote) {
        BigDecimal asked = amount == null ? null : amount.setScale(2, RoundingMode.HALF_UP);
        if (asked == null || asked.signum() <= 0) {
            throw new IllegalArgumentException("A cash-out has to be more than nothing");
        }
        if (asked.compareTo(minimumCashOut) < 0) {
            throw new IllegalArgumentException(
                    "The smallest cash-out is " + minimumCashOut + " " + currency);
        }

        BigDecimal available = availableFor(riderRef);
        if (asked.compareTo(available) > 0) {
            // The available figure is quoted back because the rider's screen may be seconds stale
            // — a job that has just settled, or cash they have just collected — and "not enough"
            // with no number is the least useful thing this could say.
            throw new IllegalArgumentException(
                    "You can take out " + available.max(BigDecimal.ZERO) + " " + currency
                            + " at the moment");
        }

        RiderCashOut request = new RiderCashOut(riderRef, asked, currency, sanitise(payoutNote));
        try {
            // Flushed here and not at commit: this insert is the serialisation point, and letting
            // it drift to the end of the transaction would put it AFTER the hold, which is the one
            // ordering that lets two requests both write one.
            cashOuts.saveAndFlush(request);
        } catch (DataIntegrityViolationException e) {
            throw new IllegalStateException(
                    "You already have a cash-out on its way. It has to be settled before you can "
                            + "ask for another.");
        }

        ledger.save(RiderLedgerEntry.cashOutHeld(riderRef, request.getId(), asked, currency));

        log.info("Rider {} requested a cash-out of {} {}", riderRef, asked, currency);
        return request;
    }

    /**
     * Pays a cash-out through whichever provider is configured.
     *
     * <p>The provider is asked FIRST and the row is only advanced if it says the money moved. The
     * other order — mark paid, then pay — leaves a rider recorded as paid when the provider
     * refused, and the only way anybody finds out is the rider asking where their money is.
     *
     * <p>A refusal is not an exception: it leaves the request open and the money still held, which
     * is the correct state for something an operator will retry.
     */
    @Transactional
    public RiderCashOut payCashOut(UUID id, String by, String operatorReference) {
        RiderCashOut request = load(id);
        if (!request.isOpen()) {
            throw new IllegalStateException("Cannot pay a cash-out that is " + request.getStatus());
        }

        RiderPayoutProvider provider = payoutProviders.current();
        RiderPayoutProvider.Payout outcome = provider.pay(new RiderPayoutProvider.PayoutRequest(
                request.getId(), request.getRiderRef(), request.getAmount(), request.getCurrency(),
                request.getPayoutNote(), sanitise(operatorReference)));

        if (!outcome.settled()) {
            throw new IllegalStateException(
                    "The payout provider refused: " + outcome.failureReason());
        }

        request.markPaid(by, outcome.provider(), outcome.reference());
        // Zero-amount, for the history. The balance already fell when the hold was written and
        // taking it again would charge the rider twice for one payout.
        ledger.save(RiderLedgerEntry.cashOutPaid(
                request.getRiderRef(), request.getId(), request.getCurrency()));
        return request;
    }

    /** Refuses a cash-out and gives the held money back. */
    @Transactional
    public RiderCashOut rejectCashOut(UUID id, String by, String note) {
        RiderCashOut request = load(id);
        request.reject(by, sanitise(note));
        ledger.save(RiderLedgerEntry.cashOutReleased(request.getRiderRef(), request.getId(),
                request.getAmount(), request.getCurrency()));
        log.info("Cash-out {} for rider {} refused", id, request.getRiderRef());
        return request;
    }

    @Transactional(readOnly = true)
    public Optional<RiderCashOut> openCashOutFor(String riderRef) {
        return cashOuts.findFirstByRiderRefAndStatus(riderRef, RiderCashOut.Status.REQUESTED);
    }

    @Transactional(readOnly = true)
    public List<RiderCashOut> cashOutsFor(String riderRef, int limit) {
        return cashOuts.findByRiderRefOrderByRequestedAtDesc(riderRef, PageRequest.of(0, limit));
    }

    /** The operator's queue: everything waiting on a payout, oldest first. */
    @Transactional(readOnly = true)
    public List<RiderCashOut> cashOutQueue(int limit) {
        return cashOuts.findByStatusOrderByRequestedAtAsc(
                RiderCashOut.Status.REQUESTED, PageRequest.of(0, limit));
    }

    public BigDecimal minimumCashOut() {
        return minimumCashOut;
    }

    public boolean payoutIsAutomated() {
        return payoutProviders.isAutomated();
    }

    private RiderCashOut load(UUID id) {
        return cashOuts.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No such cash-out: " + id));
    }

    /**
     * Trims free text typed by a rider or an operator down to something safe to store and return.
     *
     * <p>Capped, control characters removed, and angle brackets dropped. A payout note is an
     * instruction — a wallet handle, a branch, a reference — and never markup, so nothing real is
     * lost; what is gained is that this string cannot carry a tag into whichever app renders it,
     * and this service does not control that app. Length is capped because the column is text and
     * an unbounded field on a public endpoint is a free write amplifier.
     */
    private static String sanitise(String text) {
        if (text == null) {
            return null;
        }
        String cleaned = text.replaceAll("[\\p{Cntrl}<>]", " ").strip();
        if (cleaned.length() > MAX_NOTE) {
            cleaned = cleaned.substring(0, MAX_NOTE);
        }
        return cleaned.isEmpty() ? null : cleaned;
    }

    /** Money is always two places. A total that renders as 12.5 in one screen and 12.50 in another
     *  invites the question of which one is right. */
    private static BigDecimal scale(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }
}
