package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatEntry.HolderKind;
import com.delivery.accounting.domain.CashFloatEntry.Kind;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * A delivery company's view of the cash its riders collect for it, and the Back Office's view of
 * what each company holds.
 *
 * <p>Read-only: the one write — a rider handing cash to the company — is
 * {@link CashFloatService#handOver}, beside the remittance it mirrors, so the two ways of clearing
 * a float share one set of locks and one set of rules.
 *
 * <p><strong>Every figure here is a fact the ledger holds, and nothing else.</strong> The design
 * this serves draws a 15% commission column, a rider-earnings column, bonuses, penalties and a
 * disputed total. None of them exists in this platform's books: a rider's pay from their company is
 * the company's employment contract (see {@code RiderLedgerEntry.PayableBy.CARRIER}), the platform's
 * cut on a catalog order cannot be separated from the goods commission, and there is no dispute
 * record at all. So what this answers is: how much cash each rider holds for the company, how old it
 * is, what they collected and handed over on a day, and what the platform credited the company for
 * that rider's jobs — the one per-rider money figure it can state truthfully.
 *
 * <p><strong>Scoped by the float's own {@code carrier_ref}</strong>, stamped when the cash was
 * collected, never by where a rider rides today. A rider who moved to another company last week
 * with notes in their pocket is still this company's to chase, and their new company cannot see it.
 *
 * <h2>Building on this: rider payroll</h2>
 * <p>A pay run that nets the cash a rider holds against their pay uses this model and adds nothing
 * beside it:
 * <ul>
 *   <li><strong>Read</strong> what each rider holds with {@link #heldByRider} (or one rider's
 *       {@link RiderSettlement#holding()}). It is exactly what a hand-over would clear right now.</li>
 *   <li><strong>Net it</strong> only through {@link CashFloatService#handOver}, passing the figure
 *       printed on the payslip as {@code expected}. A deduction IS a hand-over — the company kept
 *       the rider's cash out of their pay, so the cash is now in the company's custody and owed to
 *       the platform — and going through it keeps the row lock, the refusal when the rider
 *       collected more since the run was drafted, and the transfer row the statements read.</li>
 *   <li><strong>Key it</strong> with a {@code requestKey} derived from the pay run and the rider, so
 *       processing the same run twice answers with the first deduction instead of taking a second.</li>
 *   <li><strong>Say how</strong> with a {@link CashFloatEntry.Method}: add a value such as
 *       {@code PAYROLL_DEDUCTION} to the enum and to {@code chk_float_method} in payroll's own
 *       migration. Never write {@code cash_float} rows directly, and never clear a collection by
 *       any other path: that is how a rider ends up chased for cash already taken from their pay.</li>
 * </ul>
 */
@Service
public class CarrierCashService {

    /** The most hand-overs one history returns. A counter's week, not an archive. */
    static final int MAX_HISTORY = 100;

    /** The most payments to the platform the "what you owe" view lists. */
    private static final int MAX_PAYMENTS = 20;

    private final CashFloatRepository floats;
    private final RiderLedgerRepository riderLedger;
    private final AccountDirectory accounts;
    private final int overdueAfterHours;
    private final ZoneId zone;
    private final String currency;
    private final Clock clock;

    @Autowired
    public CarrierCashService(CashFloatRepository floats,
                              RiderLedgerRepository riderLedger,
                              AccountDirectory accounts,
                              // How long cash may be held before it is overdue. The same number
                              // the Back Office list is flagged with, so both sides of a hand-over
                              // agree on what "late" means.
                              @Value("${delivery.accounting.float.overdue-after-hours:48}")
                              int overdueAfterHours,
                              // A "day" on this page is a local-calendar day, in the same zone the
                              // statements use.
                              @Value("${delivery.accounting.statements.zone:UTC}") String zone,
                              @Value("${delivery.accounting.currency:USD}") String currency) {
        this(floats, riderLedger, accounts, overdueAfterHours, zone, currency, Clock.systemUTC());
    }

    /** For tests, which need "now" to hold still while they ask how old something is. */
    CarrierCashService(CashFloatRepository floats, RiderLedgerRepository riderLedger,
                       AccountDirectory accounts, int overdueAfterHours, String zone,
                       String currency, Clock clock) {
        this.floats = floats;
        this.riderLedger = riderLedger;
        this.accounts = accounts;
        this.overdueAfterHours = overdueAfterHours;
        this.zone = ZoneId.of(zone);
        this.currency = currency;
        this.clock = clock;
    }

    public int overdueAfterHours() {
        return overdueAfterHours;
    }

    public ZoneId zone() {
        return zone;
    }

    public String currency() {
        return currency;
    }

    /** Today, in the calendar this page reads days in. */
    public LocalDate today() {
        return LocalDate.now(clock.withZone(zone));
    }

    /**
     * Whether cash collected at {@code oldest} has been held past the line.
     *
     * <p>Strictly past it: cash held for exactly the limit is on time, and one second more is not.
     * A missing timestamp is never overdue — a row that has not been read back yet is new.
     */
    public boolean isOverdue(Instant oldest) {
        return oldest != null
                && oldest.isBefore(clock.instant().minus(Duration.ofHours(overdueAfterHours)));
    }

    // ---------------------------------------------------------------------------- the overview

    /** Where one rider stands with the company. */
    public enum Standing {
        /** Holding the company's cash, inside the limit. */
        HOLDING,
        /** Holding cash older than the limit. */
        OVERDUE,
        /** Holding none of the company's cash. */
        SETTLED
    }

    /**
     * The reconciliation page.
     *
     * @param day the calendar day the collected, earned and handed-over figures cover. The balances
     *            are always as of now: cash collected on Monday and still held on Wednesday is
     *            Wednesday's problem whichever day is being looked at
     */
    public record Overview(LocalDate day, String currency, int overdueAfterHours, Totals totals,
                           List<RiderRow> riders) {
    }

    /**
     * The four headline figures.
     *
     * @param withRiders    cash this company's riders still hold for it, right now
     * @param ridersHolding how many riders that is
     * @param handedOver    what riders handed to the company on the day
     * @param handovers     in how many hand-overs
     * @param held          what the company itself holds — handed over and not yet paid to the
     *                      platform. This is what it owes the platform right now
     * @param heldOrders    across how many orders
     * @param overdue       cash with riders past the limit, counted per collection rather than per
     *                      rider, so one old order does not make a rider's whole bag "overdue"
     * @param overdueRiders how many riders hold any of it
     */
    public record Totals(BigDecimal withRiders, int ridersHolding, BigDecimal handedOver,
                         int handovers, BigDecimal held, int heldOrders, BigDecimal overdue,
                         int overdueRiders) {
    }

    /**
     * One rider's line.
     *
     * @param name          what Keycloak calls them, or null when it knows no name
     * @param collected     door cash they took for the company on the day
     * @param collections   in how many orders
     * @param earned        what the platform credited the company for their jobs on the day
     * @param jobs          how many jobs that was
     * @param holding       the company's cash they hold right now, whenever they took it
     * @param orders        across how many orders
     * @param oldest        when the oldest of it was collected; null when they hold none
     * @param overdueHours  how long the oldest has been held, only when that is past the limit
     */
    public record RiderRow(String riderRef, String name, BigDecimal collected, int collections,
                           BigDecimal earned, int jobs, BigDecimal holding, int orders,
                           Instant oldest, Instant lastHandoverAt, Standing standing,
                           Long overdueHours) {
    }

    @Transactional(readOnly = true)
    public Overview overview(String carrierRef, LocalDate day) {
        Instant from = day.atStartOfDay(zone).toInstant();
        Instant to = day.plusDays(1).atStartOfDay(zone).toInstant();

        Map<String, List<CashFloatEntry>> heldBy = byHolder(floats.heldByRidersFor(carrierRef));
        Map<String, List<CashFloatEntry>> collectedBy = byHolder(
                floats.forCarrierBetween(carrierRef, HolderKind.RIDER, Kind.COLLECTED, from, to));
        List<CashFloatEntry> handovers =
                floats.forCarrierBetween(carrierRef, HolderKind.RIDER, Kind.TRANSFERRED, from, to);
        Map<String, List<RiderLedgerEntry>> jobsBy = riderLedger
                .jobsForCarrierBetween(carrierRef, from, to).stream()
                .collect(Collectors.groupingBy(RiderLedgerEntry::getRiderRef, LinkedHashMap::new,
                        Collectors.toList()));
        Map<String, Instant> lastHandover = instants(floats.lastHandoverByRider(carrierRef));

        // Everyone who has ever carried cash for the company, plus anyone who worked for it on the
        // day without taking cash, so a card-only shift still shows its earnings.
        Set<String> riders = new LinkedHashSet<>(floats.ridersCarryingFor(carrierRef));
        riders.addAll(jobsBy.keySet());

        List<RiderRow> rows = new ArrayList<>();
        BigDecimal overdueTotal = BigDecimal.ZERO;
        int overdueRiders = 0;
        for (String rider : riders) {
            List<CashFloatEntry> held = heldBy.getOrDefault(rider, List.of());
            List<CashFloatEntry> collected = collectedBy.getOrDefault(rider, List.of());
            List<RiderLedgerEntry> jobs = jobsBy.getOrDefault(rider, List.of());

            BigDecimal late = sum(held.stream().filter(f -> isOverdue(f.getCreatedAt())).toList());
            if (late.signum() > 0) {
                overdueTotal = overdueTotal.add(late);
                overdueRiders++;
            }
            Instant oldest = oldest(held);
            Standing standing = held.isEmpty()
                    ? Standing.SETTLED
                    : (late.signum() > 0 ? Standing.OVERDUE : Standing.HOLDING);

            rows.add(new RiderRow(rider, nameOf(rider),
                    sum(collected), collected.size(),
                    money(jobs.stream().map(RiderLedgerEntry::getAmount)
                            .reduce(BigDecimal.ZERO, BigDecimal::add)),
                    jobs.size(),
                    sum(held), held.size(), oldest, lastHandover.get(rider), standing,
                    standing == Standing.OVERDUE
                            ? Duration.between(oldest, clock.instant()).toHours()
                            : null));
        }

        // The work list order: the overdue first, oldest first; then whoever holds the most; then
        // the square, by name. The biggest bag is usually just the busiest rider — the oldest one is
        // the question worth asking.
        rows.sort(Comparator
                .comparingInt((RiderRow r) -> rank(r.standing()))
                .thenComparing(RiderRow::oldest, Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(RiderRow::holding, Comparator.reverseOrder())
                .thenComparing(r -> r.name() == null ? r.riderRef() : r.name()));

        List<CashFloatEntry> custody = floats.heldBy(carrierRef);
        Totals totals = new Totals(
                money(rows.stream().map(RiderRow::holding).reduce(BigDecimal.ZERO, BigDecimal::add)),
                (int) rows.stream().filter(r -> r.holding().signum() > 0).count(),
                sum(handovers), handovers.size(),
                sum(custody), custody.size(),
                money(overdueTotal), overdueRiders);

        return new Overview(day, currency, overdueAfterHours, totals, List.copyOf(rows));
    }

    // ------------------------------------------------------------------------ one rider's page

    /**
     * One rider's settlement page.
     *
     * @param holding      what they hold for the company now — the amount a hand-over clears
     * @param earnedOnHeld what the platform credited the company for the jobs behind that cash, where
     *                     the ledger has a figure. Informational: none of it is the rider's to keep
     * @param firstSeenAt  when they first collected cash for the company
     */
    public record RiderSettlement(String riderRef, String name, String currency,
                                  int overdueAfterHours, BigDecimal holding,
                                  BigDecimal earnedOnHeld, Standing standing, Long overdueHours,
                                  List<HeldCollection> held, List<HandoverView> handovers,
                                  Instant firstSeenAt) {
    }

    /**
     * One order's cash still in the rider's bag.
     *
     * @param earned the company's credit for the job, or null when the ledger has none — a job with
     *               no delivery fee writes no row, and "we have no figure" is not "zero"
     */
    public record HeldCollection(UUID orderId, BigDecimal amount, Instant collectedAt,
                                 BigDecimal earned, boolean overdue) {
    }

    /** A recorded hand-over, as the history lists it. */
    public record HandoverView(UUID id, String riderRef, String riderName, BigDecimal amount,
                               int collections, CashFloatEntry.Method method, String note,
                               String recordedBy, String recordedByName, Instant at) {
    }

    /**
     * Whether this rider has ever worked for this company: carried cash for it, or done a job for it.
     *
     * <p>Both, because the overview lists both. A rider whose shifts were all card orders has no
     * float row, yet appears on the company's list with the day's jobs; opening their page must
     * show "nothing held", not "never heard of them". Anyone else — a rival's rider, a platform-fleet
     * rider, an id that does not exist — is not this company's to look at.
     */
    @Transactional(readOnly = true)
    public boolean carriesFor(String carrierRef, String riderRef) {
        return floats.existsByCarrierRefAndHolderRefAndHolderKind(
                        carrierRef, riderRef, HolderKind.RIDER)
                || riderLedger.existsByRiderRefAndCarrierRefAndFleet(
                        riderRef, carrierRef, RiderLedgerEntry.Fleet.CARRIER);
    }

    /**
     * @return empty when the rider has never carried cash for this company. Not "settled": the
     *         caller answers 404, because whether a stranger rides for somebody else is not this
     *         company's to learn
     */
    @Transactional(readOnly = true)
    public Optional<RiderSettlement> rider(String carrierRef, String riderRef) {
        if (!carriesFor(carrierRef, riderRef)) {
            return Optional.empty();
        }

        List<CashFloatEntry> held = floats.heldForCarrier(riderRef, carrierRef);
        Map<UUID, BigDecimal> earnedOn = earnedOn(carrierRef, riderRef, held);

        List<HeldCollection> collections = held.stream()
                .map(f -> new HeldCollection(f.getOrderId(), money(f.getAmount()), f.getCreatedAt(),
                        earnedOn.get(f.getOrderId()), isOverdue(f.getCreatedAt())))
                .toList();

        Instant oldest = oldest(held);
        boolean late = held.stream().anyMatch(f -> isOverdue(f.getCreatedAt()));
        Standing standing = held.isEmpty()
                ? Standing.SETTLED
                : (late ? Standing.OVERDUE : Standing.HOLDING);

        List<CashFloatEntry> transfers = floats
                .findByCarrierRefAndHolderRefAndEntryKindOrderByCreatedAtDesc(
                        carrierRef, riderRef, Kind.TRANSFERRED, PageRequest.of(0, MAX_HISTORY));

        return Optional.of(new RiderSettlement(riderRef, nameOf(riderRef), currency,
                overdueAfterHours, sum(held),
                money(earnedOn.values().stream().reduce(BigDecimal.ZERO, BigDecimal::add)),
                standing,
                standing == Standing.OVERDUE
                        ? Duration.between(oldest, clock.instant()).toHours()
                        : null,
                collections, views(transfers), firstSeen(held, transfers)));
    }

    /** The company's hand-overs from every rider, newest first. */
    @Transactional(readOnly = true)
    public List<HandoverView> history(String carrierRef, int limit) {
        int capped = Math.max(1, Math.min(limit, MAX_HISTORY));
        return views(floats.findByCarrierRefAndEntryKindOrderByCreatedAtDesc(
                carrierRef, Kind.TRANSFERRED, PageRequest.of(0, capped)));
    }

    // --------------------------------------------------------------------- what the company owes

    /**
     * What a company owes the platform, and what it has paid.
     *
     * @param held          handed over by its riders and not yet paid — owed now
     * @param withRiders    still in its riders' pockets. The company answers for it, but it is not
     *                      owed until it is handed over, so it is reported beside {@code held} and
     *                      never added to it
     * @param payments      its payments to the platform, newest first. Who at the platform recorded
     *                      each one is deliberately not included: that is an operator's identity,
     *                      not the company's business
     */
    public record Owed(String currency, int overdueAfterHours, BigDecimal held, int orders,
                       Instant oldest, boolean overdue, BigDecimal withRiders, int ridersHolding,
                       List<Payment> payments) {
    }

    /** One payment a company made to the platform. */
    public record Payment(UUID id, BigDecimal amount, int collections,
                          CashFloatEntry.Method method, Instant at) {
    }

    @Transactional(readOnly = true)
    public Owed owed(String carrierRef) {
        List<CashFloatEntry> custody = floats.heldBy(carrierRef);
        List<CashFloatEntry> withRiders = floats.heldByRidersFor(carrierRef);
        List<CashFloatEntry> remittances = floats
                .findByHolderRefAndHolderKindAndEntryKindOrderByCreatedAtDesc(
                        carrierRef, HolderKind.PROVIDER, Kind.REMITTED,
                        PageRequest.of(0, MAX_PAYMENTS));
        Map<UUID, Integer> covered = clearedCounts(ids(remittances));

        Instant oldest = oldest(custody);
        return new Owed(currency, overdueAfterHours, sum(custody), custody.size(), oldest,
                isOverdue(oldest), sum(withRiders),
                (int) withRiders.stream().map(CashFloatEntry::getHolderRef).distinct().count(),
                remittances.stream()
                        .map(r -> new Payment(r.getId(), money(r.getAmount()),
                                covered.getOrDefault(r.getId(), 0), r.getMethod(),
                                r.getCreatedAt()))
                        .toList());
    }

    /**
     * What each of this company's riders holds for it right now, keyed by rider, oldest holder's
     * cash first — the read a pay run nets against pay. See the class note for the write side.
     *
     * <p>Only riders holding something appear; a rider absent from the map holds nothing for this
     * company. Each figure is exactly what {@link CashFloatService#handOver} would clear for that
     * rider at this moment, so it is safe to pass straight back as the hand-over's expected amount.
     * Cash the same rider holds for the platform's own fleet or for another company is not in it.
     */
    @Transactional(readOnly = true)
    public Map<String, BigDecimal> heldByRider(String carrierRef) {
        Map<String, BigDecimal> out = new LinkedHashMap<>();
        byHolder(floats.heldByRidersFor(carrierRef))
                .forEach((rider, rows) -> out.put(rider, sum(rows)));
        return out;
    }

    // -------------------------------------------------------------------------- the Back Office

    /**
     * One delivery company's cash, as the Back Office sees it.
     *
     * @param held       what the company holds and owes the platform now
     * @param withRiders what its riders still hold for it
     * @param lastPaidAt when it last paid the platform; null if it never has
     */
    public record CarrierHolding(String carrierRef, BigDecimal held, int orders, Instant oldest,
                                 boolean overdue, BigDecimal withRiders, int ridersHolding,
                                 Instant ridersOldest, Instant lastPaidAt) {
    }

    /**
     * Every company holding cash, or with riders who are — largest custody first.
     *
     * <p>Built from the same rows the Back Office's cash-on-hand list is, so the two cannot disagree:
     * a company's custody is its line in that list, and its riders' cash is theirs.
     */
    @Transactional(readOnly = true)
    public List<CarrierHolding> carriers() {
        Map<String, CashFloatRepository.HolderBalance> custody = new LinkedHashMap<>();
        for (CashFloatRepository.HolderBalance row : floats.outstandingByHolder()) {
            if (row.getHolderKind() == HolderKind.PROVIDER) {
                custody.put(row.getHolderRef(), row);
            }
        }
        Map<String, Object[]> riders = new HashMap<>();
        for (Object[] row : floats.withRidersByCarrier()) {
            riders.put((String) row[0], row);
        }
        Map<String, Instant> lastPaid = instants(floats.lastRemittedByCarrier());

        Set<String> refs = new LinkedHashSet<>(custody.keySet());
        refs.addAll(riders.keySet());

        List<CarrierHolding> out = new ArrayList<>();
        for (String ref : refs) {
            CashFloatRepository.HolderBalance own = custody.get(ref);
            Object[] theirs = riders.get(ref);
            Instant oldest = own == null ? null : own.getOldest();
            out.add(new CarrierHolding(ref,
                    own == null ? money(BigDecimal.ZERO) : money(own.getAmount()),
                    own == null ? 0 : (int) own.getOrders(),
                    oldest, isOverdue(oldest),
                    theirs == null ? money(BigDecimal.ZERO) : money((BigDecimal) theirs[1]),
                    theirs == null ? 0 : ((Number) theirs[2]).intValue(),
                    theirs == null ? null : (Instant) theirs[3],
                    lastPaid.get(ref)));
        }
        out.sort(Comparator.comparing(CarrierHolding::held).reversed()
                .thenComparing(CarrierHolding::withRiders, Comparator.reverseOrder()));
        return out;
    }

    // ------------------------------------------------------------------------------- plumbing

    private List<HandoverView> views(List<CashFloatEntry> transfers) {
        Map<UUID, Integer> covered = clearedCounts(ids(transfers));
        return transfers.stream()
                .map(t -> new HandoverView(t.getId(), t.getHolderRef(), nameOf(t.getHolderRef()),
                        money(t.getAmount()), covered.getOrDefault(t.getId(), 0), t.getMethod(),
                        t.getNote(), t.getRecordedBy(),
                        t.getRecordedBy() == null ? null : nameOf(t.getRecordedBy()),
                        t.getCreatedAt()))
                .toList();
    }

    /** The company's credit for each held order, from the rider's own job rows. */
    private Map<UUID, BigDecimal> earnedOn(String carrierRef, String riderRef,
                                           List<CashFloatEntry> held) {
        Set<UUID> orderIds = held.stream()
                .map(CashFloatEntry::getOrderId)
                .filter(java.util.Objects::nonNull)
                .collect(Collectors.toSet());
        if (orderIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, BigDecimal> out = new HashMap<>();
        for (RiderLedgerEntry e : riderLedger.findByRiderRefAndOrderIdIn(riderRef, orderIds)) {
            if (e.getEntryType() == RiderLedgerEntry.EntryType.JOB_EARNING
                    && carrierRef.equals(e.getCarrierRef())) {
                out.putIfAbsent(e.getOrderId(), money(e.getAmount()));
            }
        }
        return out;
    }

    /**
     * When the rider first carried cash for the company, as far as the rows loaded can say — the
     * oldest of what they hold and of the hand-overs listed. Enough for "since"; not a hire date.
     */
    private static Instant firstSeen(List<CashFloatEntry> held, List<CashFloatEntry> transfers) {
        Instant first = oldest(held);
        for (CashFloatEntry t : transfers) {
            if (t.getCreatedAt() != null && (first == null || t.getCreatedAt().isBefore(first))) {
                first = t.getCreatedAt();
            }
        }
        return first;
    }

    private Map<UUID, Integer> clearedCounts(Collection<UUID> ids) {
        if (ids.isEmpty()) {
            return Map.of();
        }
        Map<UUID, Integer> out = new HashMap<>();
        for (Object[] row : floats.countClearedBy(ids)) {
            out.put((UUID) row[0], ((Number) row[1]).intValue());
        }
        return out;
    }

    private static List<UUID> ids(List<CashFloatEntry> rows) {
        return rows.stream().map(CashFloatEntry::getId).toList();
    }

    /** A person's display name from Keycloak, or null. Never the raw id dressed up as a name. */
    private String nameOf(String subject) {
        String name = accounts.profileOf(subject).name();
        return name == null || name.isBlank() ? null : name;
    }

    private static Map<String, List<CashFloatEntry>> byHolder(List<CashFloatEntry> rows) {
        return rows.stream().collect(Collectors.groupingBy(CashFloatEntry::getHolderRef,
                LinkedHashMap::new, Collectors.toList()));
    }

    private static Map<String, Instant> instants(List<Object[]> rows) {
        return rows.stream()
                .filter(row -> row[0] != null && row[1] != null)
                .collect(Collectors.toMap(row -> (String) row[0], row -> (Instant) row[1],
                        (a, b) -> a.isAfter(b) ? a : b));
    }

    private static Instant oldest(List<CashFloatEntry> rows) {
        return rows.stream()
                .map(CashFloatEntry::getCreatedAt)
                .filter(java.util.Objects::nonNull)
                .min(Comparator.naturalOrder())
                .orElse(null);
    }

    private static BigDecimal sum(List<CashFloatEntry> rows) {
        return money(rows.stream()
                .map(CashFloatEntry::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add));
    }

    private static BigDecimal money(BigDecimal amount) {
        return (amount == null ? BigDecimal.ZERO : amount).setScale(2, RoundingMode.HALF_UP);
    }

    /** The work-list order of a standing: overdue, then holding, then square. */
    private static int rank(Standing standing) {
        return switch (standing) {
            case OVERDUE -> 0;
            case HOLDING -> 1;
            case SETTLED -> 2;
        };
    }
}
