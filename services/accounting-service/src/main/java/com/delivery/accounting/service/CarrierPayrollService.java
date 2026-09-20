package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.accounting.domain.CarrierPayAdjustment;
import com.delivery.accounting.domain.CarrierPayAdjustmentRepository;
import com.delivery.accounting.domain.CarrierPayAttendance;
import com.delivery.accounting.domain.CarrierPayAttendanceRepository;
import com.delivery.accounting.domain.CarrierPayDelivered;
import com.delivery.accounting.domain.CarrierPayDeliveredRepository;
import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayLine.Source;
import com.delivery.accounting.domain.CarrierPayLineRepository;
import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayPolicy.PayCycle;
import com.delivery.accounting.domain.CarrierPayPolicyRepository;
import com.delivery.accounting.domain.CarrierPayRun;
import com.delivery.accounting.domain.CarrierPayRun.Attendance;
import com.delivery.accounting.domain.CarrierPayRun.Deliveries;
import com.delivery.accounting.domain.CarrierPayRun.Status;
import com.delivery.accounting.domain.CarrierPayRunRepository;
import com.delivery.accounting.domain.CarrierPayrollEvent;
import com.delivery.accounting.domain.CarrierPayrollEvent.Action;
import com.delivery.accounting.domain.CarrierPayrollEventRepository;
import com.delivery.accounting.domain.CarrierPayslip;
import com.delivery.accounting.domain.CarrierPayslipRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.service.PayslipCalculator.RiderHours;
import com.delivery.accounting.service.RiderAttendanceSource.AttendanceRead;
import com.delivery.accounting.service.RiderDeliveriesSource.DeliveriesRead;

/**
 * A delivery company's payroll for the riders it employs: its pay rules, one run per pay period,
 * and the payments it records.
 *
 * <h2>Not the platform's money</h2>
 * <p>What a company pays its riders is its own employment contract ({@code PayableBy.CARRIER}).
 * Nothing here writes a ledger leg, a rider balance or a bank posting; a payslip marked paid records
 * that the company paid, outside this system. The one place payroll touches the platform's books is
 * cash a rider collected for the company by the end of the period and still holds, kept out of their
 * pay — and that goes through the custody model's own door, {@link CashFloatService#handOver},
 * exactly as {@link CarrierCashService} documents: the payslip's figure as the expected amount, the
 * period's end as the cut-off, and a request key derived from the run and the rider
 * ({@link #payrollKey}), so the same run can never take the same cash twice. Cash collected after the
 * period is not the run's: it neither moves the figures being approved nor leaves the rider's bag.
 *
 * <h2>Draft, approved, paid</h2>
 * <p>A draft is recomputed as often as the company likes. Approving it computes it once more and
 * refuses if anything moved since the approver looked — a delivery that reached the ledger late,
 * cash handed over at the hub, a correction paid in another run, new rules — so what is frozen is
 * what was seen. Approval nets the cash first, then freezes the payslips. After that the figures
 * never change: payments are recorded against them, and a mistake is a correction paid in a later
 * run.
 *
 * <h2>Hours are a snapshot</h2>
 * <p>Attendance for a period keeps changing after it ends — a night shift's 00:10 arrival, an open
 * session, an office entry made weeks later. So starting or recomputing a draft copies the totals
 * into the run with the time they were read; editing its lines and approving it use that copy; and
 * only an explicit recompute reads them again. If attendance cannot be read the run computes
 * without hours, says so, and approving it has to acknowledge that.
 *
 * <h2>A delivery is an order, not a fee</h2>
 * <p>Deliveries are counted from Order Manager ({@link RiderDeliveriesSource}): every order a rider
 * delivered for the company in the period, whatever it earned. The ledger's JOB_EARNING rows are not
 * that — a free delivery has none — so they only stand in when Order Manager cannot be asked, and a
 * run counted from them says so and needs acknowledging. The count is a copy, like the hours, and a
 * draft last read before its period ended is recomputed before it can be approved: a copy stops at
 * the moment it was taken.
 *
 * <h2>No network inside a transaction</h2>
 * <p>The attendance read happens before a transaction opens, never while a pooled connection and a
 * run's row lock wait on another service. That is why the boundaries here are explicit templates
 * rather than annotations: where a transaction starts is part of the design, not a proxy detail.
 */
@Service
public class CarrierPayrollService {

    /** How many pay periods the period list goes back, the current one included. */
    static final int PERIODS = 8;
    /** The most audit entries one run's page lists. */
    static final int HISTORY = 50;
    /** How many versions of the rules the rules page lists. */
    static final int POLICY_HISTORY = 12;
    /** How many start days the rules form offers per calendar. */
    static final int START_OPTIONS = 4;
    /** A fat-finger guard on a typed amount, not a policy about pay. */
    static final BigDecimal MAX_AMOUNT = new BigDecimal("100000.00");
    static final BigDecimal MAX_MULTIPLIER = new BigDecimal("5.00");
    static final int MAX_LABEL = 120;
    static final int MAX_REASON = 500;
    static final int MAX_REFERENCE = 120;

    private static final BigDecimal ZERO = BigDecimal.ZERO.setScale(2);

    private final CarrierPayPolicyRepository policies;
    private final CarrierPayRunRepository runs;
    private final CarrierPayslipRepository payslips;
    private final CarrierPayLineRepository lines;
    private final CarrierPayAdjustmentRepository adjustments;
    private final CarrierPayAttendanceRepository snapshots;
    private final CarrierPayDeliveredRepository deliveredCopies;
    private final CarrierPayrollEventRepository events;
    private final RiderLedgerRepository riderLedger;
    private final CarrierCashService carrierCash;
    private final CashFloatService cashFloat;
    private final RiderAttendanceSource attendance;
    private final RiderDeliveriesSource deliveriesSource;
    private final AccountDirectory accounts;
    private final TransactionTemplate writeTx;
    private final TransactionTemplate readTx;
    private final ZoneId zone;
    private final String currency;
    private final Clock clock;

    @Autowired
    public CarrierPayrollService(CarrierPayPolicyRepository policies,
                                 CarrierPayRunRepository runs,
                                 CarrierPayslipRepository payslips,
                                 CarrierPayLineRepository lines,
                                 CarrierPayAdjustmentRepository adjustments,
                                 CarrierPayAttendanceRepository snapshots,
                                 CarrierPayDeliveredRepository deliveredCopies,
                                 CarrierPayrollEventRepository events,
                                 RiderLedgerRepository riderLedger,
                                 CarrierCashService carrierCash,
                                 CashFloatService cashFloat,
                                 RiderAttendanceSource attendance,
                                 RiderDeliveriesSource deliveriesSource,
                                 AccountDirectory accounts,
                                 PlatformTransactionManager transactionManager,
                                 // The calendar pay periods are in: the platform's one calendar,
                                 // which is also order-tracking's day zone (RECON-08).
                                 PlatformCalendar calendar,
                                 @Value("${delivery.accounting.currency:USD}") String currency) {
        this(policies, runs, payslips, lines, adjustments, snapshots, deliveredCopies, events,
                riderLedger, carrierCash, cashFloat, attendance, deliveriesSource, accounts,
                transactionManager, calendar.zone().getId(), currency, calendar.clock());
    }

    /** For tests, which need "today" to hold still while periods open and close around it. */
    CarrierPayrollService(CarrierPayPolicyRepository policies, CarrierPayRunRepository runs,
                          CarrierPayslipRepository payslips, CarrierPayLineRepository lines,
                          CarrierPayAdjustmentRepository adjustments,
                          CarrierPayAttendanceRepository snapshots,
                          CarrierPayDeliveredRepository deliveredCopies,
                          CarrierPayrollEventRepository events, RiderLedgerRepository riderLedger,
                          CarrierCashService carrierCash, CashFloatService cashFloat,
                          RiderAttendanceSource attendance, RiderDeliveriesSource deliveriesSource,
                          AccountDirectory accounts,
                          PlatformTransactionManager transactionManager, String zone,
                          String currency, Clock clock) {
        this.policies = policies;
        this.runs = runs;
        this.payslips = payslips;
        this.lines = lines;
        this.adjustments = adjustments;
        this.snapshots = snapshots;
        this.deliveredCopies = deliveredCopies;
        this.events = events;
        this.riderLedger = riderLedger;
        this.carrierCash = carrierCash;
        this.cashFloat = cashFloat;
        this.attendance = attendance;
        this.deliveriesSource = deliveriesSource;
        this.accounts = accounts;
        this.writeTx = new TransactionTemplate(transactionManager);
        this.readTx = new TransactionTemplate(transactionManager);
        this.readTx.setReadOnly(true);
        this.zone = ZoneId.of(zone);
        this.currency = currency;
        this.clock = clock;
    }

    public String zone() {
        return zone.getId();
    }

    public String currency() {
        return currency;
    }

    /** Today, in the payroll calendar. */
    public LocalDate today() {
        return LocalDate.now(clock.withZone(zone));
    }

    private Instant now() {
        return clock.instant();
    }

    // ------------------------------------------------------------------------------ refusals

    /**
     * Why something asked of payroll was not done. Nothing was written. The controller answers with
     * the status and the code; the page words the code.
     */
    public static class PayrollRefusal extends RuntimeException {
        private final int status;
        private final String code;
        private final transient Object detail;

        public PayrollRefusal(int status, String code, String message) {
            this(status, code, message, null);
        }

        public PayrollRefusal(int status, String code, String message, Object detail) {
            super(message);
            this.status = status;
            this.code = code;
            this.detail = detail;
        }

        public int status() {
            return status;
        }

        public String code() {
            return code;
        }

        /** Something the page can act on — the run already there, the current total — or null. */
        public Object detail() {
            return detail;
        }
    }

    private static PayrollRefusal refusal(int status, String code, String message) {
        return new PayrollRefusal(status, code, message);
    }

    /** One answer for a run that does not exist and a run of another company's. */
    private static PayrollRefusal notFound() {
        return refusal(404, "RUN_NOT_FOUND", "That pay run is not one of your company's.");
    }

    // --------------------------------------------------------------------------------- views

    public record PolicyView(CarrierPayPolicy policy, String createdByName) {
    }

    /**
     * @param current      the rules in force today, or null before the company set any
     * @param scheduled    rules set to start after today, earliest first
     * @param startOptions the days new rules could start on, per calendar
     */
    public record PolicyPage(String zone, String currency, LocalDate today, PolicyView current,
                             List<PolicyView> scheduled, List<PolicyView> history,
                             Map<PayCycle, List<LocalDate>> startOptions) {
    }

    /**
     * One pay period on the period list.
     *
     * @param aligned false for a run whose period the rules no longer draw — a draft left behind by
     *                a change of calendar, listed so it can be opened and discarded
     * @param payable null when the period has no run: nothing has been computed, which is not zero
     */
    public record PeriodRow(LocalDate from, LocalDate to, boolean over, boolean aligned,
                            CarrierPayRun run, int riders, BigDecimal payable) {
    }

    public record PeriodsPage(String zone, String currency, LocalDate today, boolean hasPolicy,
                              List<PeriodRow> periods) {
    }

    public record LineView(CarrierPayLine line, String createdByName) {
    }

    /**
     * @param hoursUnknown the rules pay or judge hours and none were read for this rider
     * @param hoursReason  why, when they are unknown: the whole read's reason, {@code UNREADABLE} for
     *                     this rider's own figures, or {@code NOT_LISTED} when attendance gave no time
     *                     of theirs with the company in the period; null otherwise
     */
    public record PayslipView(CarrierPayslip slip, String name, List<LineView> lines,
                              boolean hoursUnknown, String hoursReason, String paidByName,
                              String failedByName) {
    }

    /** A rider on a run whose hours are unknown, named for whoever approves it, and why. */
    public record MissingHours(String riderRef, String name, String reason) {
    }

    /**
     * A run's headline figures, all from its payslips.
     *
     * @param payable      what the company pays out: the positive nets
     * @param average      payable over riders; null with no riders, where there is no average
     * @param owedByRiders what deductions took beyond pay, never netted against anyone else's pay
     * @param outstanding  approved and not yet recorded as paid, failed payments included
     */
    public record Totals(int riders, BigDecimal payable, BigDecimal average, BigDecimal gross,
                         BigDecimal bonuses, BigDecimal deductions, BigDecimal owedByRiders,
                         BigDecimal tips, BigDecimal cashNetted, BigDecimal paid,
                         BigDecimal outstanding, int due, int failed, int paidCount) {
    }

    public record CorrectionView(CarrierPayAdjustment adjustment, String riderName,
                                 String createdByName) {
    }

    public record EventView(CarrierPayrollEvent event, String actorName, String riderName) {
    }

    /**
     * One run's page.
     *
     * @param jobsSinceComputed deliveries of the period that reached the ledger after the figures
     *                          were computed, when they were counted from the ledger: on a draft,
     *                          "recompute"; on an approved run, "correct". Always zero when they
     *                          were counted from orders, whose copy the ledger cannot make stale
     * @param needsAcknowledgement approving this draft means approving it without some hours, or
     *                          with deliveries counted from the ledger
     * @param periodChanged     the rules now cut this draft's days into a different period
     * @param readBeforePeriodEnd this draft's figures were last read before its period ended: it is
     *                          recomputed before it can be approved
     * @param hoursMissingFor   the riders whose hours the rules need and this run does not have, in
     *                          payslip order — one rider's, several, or everyone's when the whole
     *                          read failed
     */
    public record RunView(CarrierPayRun run, PolicyView policy, String approvedByName,
                          List<PayslipView> payslips, Totals totals,
                          List<CorrectionView> corrections, List<EventView> history,
                          boolean periodOver, long jobsSinceComputed,
                          boolean needsAcknowledgement, boolean periodChanged,
                          boolean readBeforePeriodEnd, List<MissingHours> hoursMissingFor) {
    }

    public enum ApprovalOutcome {
        APPROVED,
        /** Somebody approved it already; nothing more was done. */
        ALREADY_APPROVED,
        /** What the approver looked at is no longer true. The run now shows what is. */
        FIGURES_CHANGED,
        /**
         * Hours are missing, or deliveries were counted from the ledger, and the approver has not
         * said to approve anyway.
         */
        NEEDS_ACKNOWLEDGEMENT
    }

    public record Approval(ApprovalOutcome outcome, RunView run) {
    }

    // --------------------------------------------------------------------------------- rules

    public PolicyPage policy(String company) {
        LocalDate today = today();
        record Read(List<CarrierPayPolicy> versions, Map<PayCycle, List<LocalDate>> options) {
        }
        Read read = readTx.execute(status -> {
            List<CarrierPayPolicy> versions = versions(company);
            return new Read(versions, startOptions(company, versions, today));
        });

        TreeMap<LocalDate, CarrierPayPolicy> upcoming = new TreeMap<>();
        for (CarrierPayPolicy version : read.versions()) {
            if (version.getEffectiveFrom().isAfter(today)) {
                // Newest saved first within a day: the first seen is the one that will apply.
                upcoming.putIfAbsent(version.getEffectiveFrom(), version);
            }
        }
        return new PolicyPage(zone.getId(), currency, today,
                PayPeriods.inForce(read.versions(), today).map(this::policyView).orElse(null),
                upcoming.values().stream().map(this::policyView).toList(),
                read.versions().stream().limit(POLICY_HISTORY).map(this::policyView).toList(),
                read.options());
    }

    /**
     * Saves a new version of the company's rules.
     *
     * <p>Refused when it would start mid-period, change calendar on any day but the 1st, clash with a
     * later version's calendar, or reach back into a period whose run is already approved — any of
     * which would leave some day paid under two sets of rules, or a frozen run claiming rules it was
     * never computed with.
     */
    public PolicyView setPolicy(String company, LocalDate effectiveFrom,
                                CarrierPayPolicy.Terms asked, String actor) {
        if (effectiveFrom == null || asked == null || asked.cycle() == null) {
            throw refusal(400, "BAD_POLICY", "Say when the rules start and how often riders are paid.");
        }
        CarrierPayPolicy.Terms terms = new CarrierPayPolicy.Terms(asked.cycle(),
                amount(asked.perDeliveryRate(), true),
                asked.hourlyRate() == null ? null : amount(asked.hourlyRate(), true),
                asked.payManualHours(),
                multiplier(asked.overtimeMultiplier()),
                amount(asked.lateDeduction(), true),
                amount(asked.absenceDeduction(), true));

        CarrierPayPolicy saved = writeTx.execute(status -> {
            List<CarrierPayPolicy> versions = versions(company);
            Optional<PayrollRefusal> refused = whyNotStart(versions, latestFrozen(company),
                    effectiveFrom, terms.cycle());
            if (refused.isPresent()) {
                throw refused.get();
            }
            Instant now = now();
            CarrierPayPolicy policy = policies.save(CarrierPayPolicy.version(company, effectiveFrom,
                    terms, currency, actor, now));
            events.save(CarrierPayrollEvent.of(company, null, null, Action.POLICY_SET, actor,
                    describe(policy), now));
            return policy;
        });
        return policyView(saved);
    }

    private Map<PayCycle, List<LocalDate>> startOptions(String company,
                                                        List<CarrierPayPolicy> versions,
                                                        LocalDate today) {
        Optional<CarrierPayRun> frozen = latestFrozen(company);
        Map<PayCycle, List<LocalDate>> out = new EnumMap<>(PayCycle.class);
        for (PayCycle cycle : PayCycle.values()) {
            List<LocalDate> days = new ArrayList<>();
            LocalDate candidate = PayPeriods.containing(today, cycle).from();
            // Far enough ahead to find a few starts past an approved run, and no further.
            for (int step = 0; step < START_OPTIONS * 6 && days.size() < START_OPTIONS; step++) {
                if (whyNotStart(versions, frozen, candidate, cycle).isEmpty()) {
                    days.add(candidate);
                }
                candidate = PayPeriods.containing(candidate, cycle).to().plusDays(1);
            }
            out.put(cycle, List.copyOf(days));
        }
        return out;
    }

    private Optional<CarrierPayRun> latestFrozen(String company) {
        return runs.findFirstByCarrierRefAndStatusNotOrderByPeriodFromDesc(company, Status.DRAFT);
    }

    private static Optional<PayrollRefusal> whyNotStart(List<CarrierPayPolicy> versions,
                                                        Optional<CarrierPayRun> frozen,
                                                        LocalDate day, PayCycle cycle) {
        if (!PayPeriods.isStart(day, cycle)) {
            return Optional.of(refusal(400, "NOT_A_PERIOD_START",
                    "Pay rules start on the first day of a pay period: the 1st or the 16th when "
                            + "paying twice a month, the 1st when paying monthly."));
        }
        Optional<CarrierPayPolicy> before = PayPeriods.inForce(versions, day.minusDays(1));
        if (before.isPresent() && before.get().getPayCycle() != cycle && day.getDayOfMonth() != 1) {
            return Optional.of(refusal(400, "CALENDAR_CHANGE_NOT_ON_THE_FIRST",
                    "A change between paying twice a month and paying monthly starts on the 1st."));
        }
        CarrierPayPolicy later = null;
        for (CarrierPayPolicy version : versions) {
            if (version.getEffectiveFrom().isAfter(day)
                    && (later == null
                        || version.getEffectiveFrom().isBefore(later.getEffectiveFrom()))) {
                later = version;
            }
        }
        if (later != null && later.getPayCycle() != cycle
                && later.getEffectiveFrom().getDayOfMonth() != 1) {
            return Optional.of(refusal(409, "CONFLICTS_WITH_LATER_RULES",
                    "Rules already set to start on " + later.getEffectiveFrom()
                            + " use a calendar that could not start that day after these."));
        }
        if (frozen.isPresent() && !day.isAfter(frozen.get().getPeriodTo())) {
            return Optional.of(refusal(409, "PERIOD_APPROVED",
                    "The pay run for " + frozen.get().getPeriodFrom() + " to "
                            + frozen.get().getPeriodTo()
                            + " is already approved, so new rules can only start after it."));
        }
        return Optional.empty();
    }

    private static String describe(CarrierPayPolicy policy) {
        CarrierPayPolicy.Terms t = policy.terms();
        return "from " + policy.getEffectiveFrom() + ", " + t.cycle()
                + "; per delivery " + t.perDeliveryRate().toPlainString()
                + "; hourly " + (t.hourlyRate() == null ? "none" : t.hourlyRate().toPlainString())
                + "; typed hours " + (t.payManualHours() ? "paid" : "not paid")
                + "; overtime x" + t.overtimeMultiplier().toPlainString()
                + "; late " + t.lateDeduction().toPlainString()
                + "; absence " + t.absenceDeduction().toPlainString();
    }

    private PolicyView policyView(CarrierPayPolicy policy) {
        return new PolicyView(policy, nameOf(policy.getCreatedBy()));
    }

    private List<CarrierPayPolicy> versions(String company) {
        return policies.findByCarrierRefOrderByEffectiveFromDescCreatedAtDesc(company);
    }

    // ------------------------------------------------------------------------------- periods

    public PeriodsPage periods(String company) {
        LocalDate today = today();
        record Read(List<CarrierPayPolicy> versions, List<PayPeriods.Period> derived,
                    List<CarrierPayRun> runs, List<CarrierPayslip> slips) {
        }
        Read read = readTx.execute(status -> {
            List<CarrierPayPolicy> versions = versions(company);
            List<PayPeriods.Period> derived = derive(versions, today);
            if (derived.isEmpty()) {
                return new Read(versions, derived, List.of(), List.of());
            }
            List<CarrierPayRun> existing =
                    runs.endingOnOrAfter(company, derived.get(derived.size() - 1).from());
            List<CarrierPayslip> slips = existing.isEmpty()
                    ? List.of()
                    : payslips.findByRunIdIn(existing.stream().map(CarrierPayRun::getId).toList());
            return new Read(versions, derived, existing, slips);
        });

        Map<UUID, List<CarrierPayslip>> byRun = read.slips().stream()
                .collect(Collectors.groupingBy(CarrierPayslip::getRunId));
        List<PeriodRow> rows = new ArrayList<>();
        Set<UUID> placed = new HashSet<>();
        for (PayPeriods.Period period : read.derived()) {
            CarrierPayRun run = read.runs().stream()
                    .filter(r -> r.getPeriodFrom().equals(period.from())
                            && r.getPeriodTo().equals(period.to()))
                    .findFirst()
                    .orElse(null);
            if (run != null) {
                placed.add(run.getId());
            }
            rows.add(row(period.from(), period.to(), true, run, byRun, today));
        }
        for (CarrierPayRun run : read.runs()) {
            if (!placed.contains(run.getId())) {
                rows.add(row(run.getPeriodFrom(), run.getPeriodTo(), false, run, byRun, today));
            }
        }
        rows.sort(Comparator.comparing(PeriodRow::from, Comparator.reverseOrder()));
        return new PeriodsPage(zone.getId(), currency, today, !read.versions().isEmpty(),
                List.copyOf(rows));
    }

    private static PeriodRow row(LocalDate from, LocalDate to, boolean aligned, CarrierPayRun run,
                                 Map<UUID, List<CarrierPayslip>> byRun, LocalDate today) {
        List<CarrierPayslip> slips = run == null
                ? List.of()
                : byRun.getOrDefault(run.getId(), List.of());
        return new PeriodRow(from, to, today.isAfter(to), aligned, run, slips.size(),
                run == null ? null : totals(slips).payable());
    }

    /** Today's period and the ones before it, each cut by the rules in force at the time. */
    private static List<PayPeriods.Period> derive(List<CarrierPayPolicy> versions, LocalDate today) {
        List<PayPeriods.Period> out = new ArrayList<>();
        LocalDate cursor = today;
        while (out.size() < PERIODS) {
            Optional<PayPeriods.Period> period = PayPeriods.periodOf(versions, cursor);
            if (period.isEmpty()) {
                break;
            }
            out.add(period.get());
            cursor = period.get().from().minusDays(1);
        }
        return out;
    }

    // ---------------------------------------------------------------------------------- runs

    public Optional<RunView> run(String company, UUID runId) {
        RunData data = readTx.execute(status -> runs.findByIdAndCarrierRef(runId, company)
                .map(this::load)
                .orElse(null));
        return Optional.ofNullable(data).map(this::render);
    }

    private RunView view(String company, UUID runId) {
        return run(company, runId).orElseThrow(CarrierPayrollService::notFound);
    }

    /** Starts the draft for the period beginning on {@code periodFrom}, and computes it. */
    public RunView start(String company, LocalDate periodFrom, String actor, String bearer) {
        if (periodFrom == null) {
            throw refusal(400, "BAD_PERIOD", "Say which pay period to start, by its first day.");
        }
        CarrierPayPolicy policy = PayPeriods.inForce(versions(company), periodFrom)
                .orElseThrow(() -> refusal(409, "NO_POLICY",
                        "Set your riders' pay rules for this period before starting its pay run."));
        PayPeriods.Period period = PayPeriods.containing(periodFrom, policy.getPayCycle());
        if (!period.from().equals(periodFrom)) {
            throw refusal(400, "NOT_A_PERIOD_START",
                    "Under your pay rules this pay period starts on " + period.from() + ".");
        }
        if (period.from().isAfter(today())) {
            throw refusal(400, "FUTURE_PERIOD", "That pay period has not started yet.");
        }
        List<CarrierPayRun> overlap = runs.overlapping(company, period.from(), period.to());
        if (!overlap.isEmpty()) {
            throw new PayrollRefusal(409, "RUN_EXISTS", "This pay period already has a pay run.",
                    overlap.get(0).getId());
        }

        Hours hours = readHours(policy.terms(), company, period, bearer);
        Delivered delivered = readDelivered(company, period, bearer);
        UUID runId;
        try {
            runId = writeTx.execute(status -> {
                Instant now = now();
                CarrierPayRun run = runs.save(CarrierPayRun.draft(company, period.from(),
                        period.to(), policy.getId(), currency, actor, now));
                Computation computed = compute(company, run.getId(), policy, period, hours,
                        delivered, List.of());
                replaceFigures(run, computed, now);
                record(run, null, Action.RUN_STARTED, actor, summary(run, computed));
                return run.getId();
            });
        } catch (DataIntegrityViolationException e) {
            throw refusal(409, "RUN_EXISTS",
                    "A pay run for this period was started a moment ago. Reload to see it.");
        }
        return view(company, runId);
    }

    /** Computes a draft again from a fresh read of everything, hours included. */
    public RunView recompute(String company, UUID runId, String actor, String bearer) {
        CarrierPayRun peek = draftOf(company, runId);
        CarrierPayPolicy policy = policyFor(company, peek);
        Hours hours = readHours(policy.terms(), company, periodOf(peek), bearer);
        Delivered delivered = readDelivered(company, periodOf(peek), bearer);

        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockDraft(company, runId);
            CarrierPayPolicy current = policyFor(company, run);
            if (current.terms().needsAttendance() != policy.terms().needsAttendance()) {
                throw refusal(409, "POLICY_CHANGED",
                        "Your pay rules changed a moment ago. Recompute again.");
            }
            Computation computed = compute(company, run.getId(), current, periodOf(run), hours,
                    delivered, liveNamedLines(run));
            replaceFigures(run, computed, now());
            record(run, null, Action.RUN_RECOMPUTED, actor, summary(run, computed));
        });
        return view(company, runId);
    }

    /** Throws a draft away. Its audit trail stays. */
    public void discard(String company, UUID runId, String actor) {
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockDraft(company, runId);
            UUID id = run.getId();
            lines.deleteByRunId(id);
            payslips.deleteByRunId(id);
            snapshots.deleteByRunId(id);
            deliveredCopies.deleteByRunId(id);
            payslips.flush();
            record(run, null, Action.RUN_DISCARDED, actor, run.getPeriodFrom() + " to "
                    + run.getPeriodTo() + ", revision " + run.getRevision());
            runs.delete(run);
        });
    }

    /** A named bonus or deduction on a rider's draft payslip. */
    public RunView addLine(String company, UUID runId, String riderRef, CarrierPayLine.Kind kind,
                           String label, BigDecimal amount, String actor) {
        CarrierPayLine.Kind lineKind = named(kind);
        String words = text(label, MAX_LABEL,
                "Name the line in up to " + MAX_LABEL + " characters.");
        BigDecimal value = amount(amount, false);

        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockDraft(company, runId);
            requireOnRun(run, riderRef);
            Instant now = now();
            CarrierPayLine line = lines.save(CarrierPayLine.manual(run.getId(), riderRef, lineKind,
                    words, value, actor, now));
            List<CarrierPayLine> live = new ArrayList<>(liveNamedLines(run));
            if (live.stream().noneMatch(l -> l.getId().equals(line.getId()))) {
                live.add(line);
            }
            refigure(company, run, live, now);
            record(run, riderRef, Action.LINE_ADDED, actor,
                    lineKind + " " + value.toPlainString() + " " + words);
        });
        return view(company, runId);
    }

    /** Takes a named line off a draft. The row stays, marked removed. */
    public RunView removeLine(String company, UUID runId, UUID lineId, String actor) {
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockDraft(company, runId);
            CarrierPayLine line = lines.findByIdAndRunId(lineId, run.getId())
                    .orElseThrow(() -> refusal(404, "LINE_NOT_FOUND",
                            "That line is not on this pay run."));
            if (line.getSource() != Source.MANUAL) {
                throw refusal(409, "LINE_NOT_REMOVABLE",
                        "Only a bonus or deduction somebody added can be taken off.");
            }
            if (line.isRemoved()) {
                return;
            }
            Instant now = now();
            line.remove(actor, now);
            refigure(company, run, liveNamedLines(run).stream()
                    .filter(l -> !l.getId().equals(lineId))
                    .toList(), now);
            record(run, line.getRiderRef(), Action.LINE_REMOVED, actor, line.getKind() + " "
                    + line.getAmount().toPlainString() + " " + line.getLabel());
        });
        return view(company, runId);
    }

    /**
     * Freezes a draft, netting each rider's cash through the custody model.
     *
     * @param revision           the revision the approver looked at
     * @param acknowledgeMissing the approver has been told what is missing — some riders' hours, or
     *                           deliveries counted from the ledger — and approves anyway
     */
    public Approval approve(String company, UUID runId, int revision,
                            boolean acknowledgeMissing, String actor) {
        CarrierPayRun peek = runs.findByIdAndCarrierRef(runId, company)
                .orElseThrow(CarrierPayrollService::notFound);
        if (!peek.isDraft()) {
            return new Approval(ApprovalOutcome.ALREADY_APPROVED, view(company, runId));
        }
        if (!today().isAfter(peek.getPeriodTo())) {
            throw refusal(409, "PERIOD_OPEN", "This pay period runs until " + peek.getPeriodTo()
                    + ". Approve it once the period is over.");
        }

        ApprovalOutcome outcome = writeTx.execute(status -> {
            CarrierPayRun run = runs.lockOwned(runId, company)
                    .orElseThrow(CarrierPayrollService::notFound);
            if (!run.isDraft()) {
                return ApprovalOutcome.ALREADY_APPROVED;
            }
            if (run.getRevision() != revision) {
                return ApprovalOutcome.FIGURES_CHANGED;
            }
            // Counted and judged as they stood when read: the rest of the period is not in them, and
            // no comparison below could notice. Nothing has been written yet.
            if (readBeforeItEnded(run)) {
                throw refusal(409, "RECOMPUTE_NEEDED", "These figures were read before the period "
                        + "ended on " + run.getPeriodTo() + ". Recompute them, check them and "
                        + "approve again.");
            }

            CarrierPayPolicy policy = policyFor(company, run);
            List<CarrierPayslip> stored = payslips.findByRunIdOrderByRiderRefAsc(run.getId());
            List<CarrierPayLine> storedLines = lines.findByRunIdOrderByCreatedAtAsc(run.getId());
            // The same computation once more — with the hours and deliveries the draft holds, never
            // a live read.
            Computation fresh = compute(company, run.getId(), policy, periodOf(run),
                    storedHours(run, policy.terms()), storedDelivered(run), liveNamedLines(run));
            if (!unchanged(run, stored, storedLines, fresh)) {
                replaceFigures(run, fresh, now());
                record(run, null, Action.RUN_RECOMPUTED, actor,
                        "Figures moved before approval; " + summary(run, fresh));
                return ApprovalOutcome.FIGURES_CHANGED;
            }
            if (stored.isEmpty()) {
                throw refusal(409, "EMPTY_RUN",
                        "Nobody has pay in this period, so there is nothing to approve.");
            }
            boolean hoursMissing = policy.terms().needsAttendance()
                    && (run.getAttendance() != Attendance.INCLUDED
                        || stored.stream().anyMatch(s -> s.figures().workedSeconds() == null));
            boolean deliveriesUncounted = deliveriesUncounted(run, policy);
            if ((hoursMissing || deliveriesUncounted) && !acknowledgeMissing) {
                return ApprovalOutcome.NEEDS_ACKNOWLEDGEMENT;
            }

            // A correction carried here is paid here, once. Locked before any cash is touched, so
            // two runs carrying it serialise here and the second finds it paid.
            Set<UUID> carried = storedLines.stream()
                    .filter(l -> l.getSource() == Source.ADJUSTMENT)
                    .map(CarrierPayLine::getAdjustmentId)
                    .collect(Collectors.toSet());
            List<CarrierPayAdjustment> corrections = carried.isEmpty()
                    ? List.of()
                    : adjustments.lockAll(carried);
            if (corrections.size() != carried.size()
                    || corrections.stream().anyMatch(a -> !a.isPending())) {
                throw refusal(409, "CORRECTION_ALREADY_PAID", "A correction on this pay run was "
                        + "just paid in another one. Recompute and approve again.");
            }

            // Cash first, and nothing else written until every hand-over has gone through: a
            // refusal from the custody model — the rider collected or handed over since — leaves
            // the draft exactly as it was. In rider order, so two approvals lock riders' cash in
            // the same order and cannot deadlock.
            Map<UUID, UUID> handovers = new HashMap<>();
            Instant periodEnd = periodOf(run).endIn(zone);
            for (CarrierPayslip slip : stored) {
                if (!slip.nettedCash()) {
                    continue;
                }
                // Only what was collected by the period's end: the cash on the payslip. Whatever the
                // rider took since stays in their bag.
                CashFloatService.Handover handover = cashFloat.handOver(company,
                        slip.getRiderRef(), slip.getCashNetted(),
                        new CashFloatEntry.Recorded(actor, CashFloatEntry.Method.PAYROLL_DEDUCTION,
                                run.getPeriodFrom() + " to " + run.getPeriodTo(),
                                payrollKey(run.getId(), slip.getRiderRef())),
                        periodEnd);
                if (handover.amount().compareTo(slip.getCashNetted()) != 0) {
                    throw new IllegalStateException("The deduction recorded for "
                            + slip.getRiderRef() + " is " + handover.amount() + ", not the "
                            + slip.getCashNetted() + " on the payslip; nothing was approved");
                }
                handovers.put(slip.getId(), handover.id());
            }

            Instant now = now();
            for (CarrierPayslip slip : stored) {
                UUID handover = handovers.get(slip.getId());
                slip.approve(handover);
                if (handover != null) {
                    record(run, slip.getRiderRef(), Action.CASH_NETTED, actor,
                            slip.getCashNetted().toPlainString() + " kept from pay; hand-over "
                                    + handover);
                }
            }
            for (CarrierPayAdjustment correction : corrections) {
                correction.appliedTo(run.getId(), now);
            }
            run.approve(actor, now);
            record(run, null, Action.RUN_APPROVED, actor, "revision " + run.getRevision() + "; "
                    + stored.size() + " payslips" + (hoursMissing ? "; approved without hours" : "")
                    + (deliveriesUncounted ? "; deliveries counted from the ledger ("
                            + run.getDeliveriesNote() + ")" : ""));
            settleIfDone(run, stored, actor, now);
            return ApprovalOutcome.APPROVED;
        });
        return new Approval(outcome, view(company, runId));
    }

    /** The company recorded paying one rider. A second press records nothing new. */
    public RunView markPaid(String company, UUID runId, UUID payslipId,
                            CashFloatEntry.Method method, String reference, String actor) {
        CashFloatEntry.Method how = payoutMethod(method);
        String ref = optionalText(reference, MAX_REFERENCE,
                "A payment reference is at most " + MAX_REFERENCE + " characters.");
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockApproved(company, runId);
            List<CarrierPayslip> slips = payslips.findByRunIdOrderByRiderRefAsc(run.getId());
            CarrierPayslip slip = payslipOf(slips, payslipId);
            if (slip.getStatus() == CarrierPayslip.Status.PAID) {
                return;
            }
            if (!slip.isOutstanding()) {
                throw refusal(409, "NOTHING_DUE", "Nothing is due on this payslip.");
            }
            Instant now = now();
            slip.markPaid(how, ref, actor, now);
            record(run, slip.getRiderRef(), Action.PAYSLIP_PAID, actor, paid(slip, how, ref));
            settleIfDone(run, slips, actor, now);
        });
        return view(company, runId);
    }

    /** The company recorded a payment that did not go through. The pay is still owed. */
    public RunView markFailed(String company, UUID runId, UUID payslipId, String reason,
                              String actor) {
        String why = text(reason, MAX_REASON,
                "Say why the payment did not go through, in up to " + MAX_REASON + " characters.");
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockApproved(company, runId);
            CarrierPayslip slip = payslipOf(
                    payslips.findByRunIdOrderByRiderRefAsc(run.getId()), payslipId);
            if (slip.getStatus() == CarrierPayslip.Status.PAID) {
                throw refusal(409, "ALREADY_PAID", "This payslip is recorded as paid, and a "
                        + "recorded payment is final. Add a correction if it was wrong.");
            }
            if (!slip.isOutstanding()) {
                throw refusal(409, "NOTHING_DUE", "Nothing is due on this payslip.");
            }
            slip.markFailed(why, actor, now());
            record(run, slip.getRiderRef(), Action.PAYSLIP_FAILED, actor, why);
        });
        return view(company, runId);
    }

    /**
     * Records every payslip waiting for payment as paid, at once.
     *
     * @param expectedTotal the total the confirmation showed. If what is waiting is anything else —
     *                      somebody recorded one of them meanwhile — nothing is recorded
     */
    public RunView payAll(String company, UUID runId, BigDecimal expectedTotal,
                          CashFloatEntry.Method method, String reference, String actor) {
        CashFloatEntry.Method how = payoutMethod(method);
        String ref = optionalText(reference, MAX_REFERENCE,
                "A payment reference is at most " + MAX_REFERENCE + " characters.");
        if (expectedTotal == null) {
            throw refusal(400, "BAD_AMOUNT", "Say the total being paid, as expectedTotal.");
        }
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockApproved(company, runId);
            List<CarrierPayslip> slips = payslips.findByRunIdOrderByRiderRefAsc(run.getId());
            // Waiting, not failed: a payment that did not go through is looked at one by one.
            List<CarrierPayslip> due = slips.stream()
                    .filter(s -> s.getStatus() == CarrierPayslip.Status.DUE)
                    .toList();
            if (due.isEmpty()) {
                throw refusal(409, "NOTHING_DUE", "No payslip on this pay run is waiting for "
                        + "payment. A failed payment is recorded one payslip at a time.");
            }
            BigDecimal total = money(due.stream()
                    .map(CarrierPayslip::getNet)
                    .reduce(BigDecimal.ZERO, BigDecimal::add));
            if (total.compareTo(expectedTotal) != 0) {
                throw new PayrollRefusal(409, "TOTAL_CHANGED", "The total waiting for payment is "
                        + "now " + total.toPlainString() + ". Nothing was recorded.", total);
            }
            Instant now = now();
            for (CarrierPayslip slip : due) {
                slip.markPaid(how, ref, actor, now);
                record(run, slip.getRiderRef(), Action.PAYSLIP_PAID, actor, paid(slip, how, ref));
            }
            settleIfDone(run, slips, actor, now);
        });
        return view(company, runId);
    }

    /** A correction to an approved run, paid in the rider's next run. */
    public RunView addCorrection(String company, UUID runId, String riderRef,
                                 CarrierPayLine.Kind kind, BigDecimal amount, String reason,
                                 String actor) {
        CarrierPayLine.Kind correctionKind = named(kind);
        BigDecimal value = amount(amount, false);
        String why = text(reason, MAX_REASON,
                "Say what the correction is for, in up to " + MAX_REASON + " characters.");
        writeTx.executeWithoutResult(status -> {
            CarrierPayRun run = lockApproved(company, runId);
            requireOnRun(run, riderRef);
            adjustments.save(CarrierPayAdjustment.of(company, run.getId(), riderRef, correctionKind,
                    value, why, actor, now()));
            record(run, riderRef, Action.ADJUSTMENT_ADDED, actor,
                    correctionKind + " " + value.toPlainString() + " " + why);
        });
        return view(company, runId);
    }

    /**
     * The request key a run's cash deduction for one rider is recorded under.
     *
     * <p>Derived, never random: the same run and rider always give the same key, so however often a
     * run's approval is retried the custody model answers with the first deduction instead of taking
     * the cash again. "payroll-" and 32 hex characters — inside the hand-over key's shape and its
     * column's 64. The prefix is reserved ({@link CashFloatService#PAYROLL_KEY_PREFIX}): no route a
     * person calls accepts it, so no counter hand-over can be recorded under a run's key first.
     */
    static String payrollKey(UUID runId, String riderRef) {
        return CashFloatService.PAYROLL_KEY_PREFIX + UUID.nameUUIDFromBytes(
                        (runId + ":" + riderRef).getBytes(StandardCharsets.UTF_8))
                .toString()
                .replace("-", "");
    }

    // ------------------------------------------------------------------------------ computing

    /**
     * The hours a computation uses, and where they came from.
     *
     * @param unreadable riders the read listed whose own figures were not believed, with why: their
     *                   hours are unknown, and nobody else's are
     */
    private record Hours(Attendance status, String note, Instant readAt,
                         Map<String, RiderHours> riders, Map<String, String> unreadable,
                         boolean fresh) {

        static Hours notNeeded() {
            return new Hours(Attendance.NOT_NEEDED, null, null, Map.of(), Map.of(), false);
        }
    }

    /** A live read. Called before any transaction opens. */
    private Hours readHours(CarrierPayPolicy.Terms terms, String company, PayPeriods.Period period,
                            String bearer) {
        if (!terms.needsAttendance()) {
            return Hours.notNeeded();
        }
        Instant at = now();
        AttendanceRead read = attendance.fleet(bearer, company, zone, period.from(), period.to());
        return read.available()
                ? new Hours(Attendance.INCLUDED, null, at, read.riders(), read.unreadable(), true)
                : new Hours(Attendance.UNAVAILABLE, read.reason(), at, Map.of(), Map.of(), true);
    }

    /** The copy a draft already holds, under the rules in force now. Never a live read. */
    private Hours storedHours(CarrierPayRun run, CarrierPayPolicy.Terms terms) {
        if (!terms.needsAttendance()) {
            return Hours.notNeeded();
        }
        return switch (run.getAttendance()) {
            // The rules came to need hours after this draft was computed: nobody has read them.
            case NOT_NEEDED -> new Hours(Attendance.UNAVAILABLE, "NOT_READ", null, Map.of(),
                    Map.of(), false);
            case UNAVAILABLE -> new Hours(Attendance.UNAVAILABLE, run.getAttendanceNote(),
                    run.getAttendanceAt(), Map.of(), Map.of(), false);
            case INCLUDED -> {
                Map<String, RiderHours> riders = new HashMap<>();
                Map<String, String> unreadable = new HashMap<>();
                for (CarrierPayAttendance row : snapshots.findByRunId(run.getId())) {
                    if (row.isReadable()) {
                        riders.put(row.getRiderRef(), new RiderHours(row.getWorkedSeconds(),
                                row.getManualSeconds(), row.getOvertimeSeconds(), row.getLates(),
                                row.getAbsences()));
                    } else {
                        unreadable.put(row.getRiderRef(), row.getUnavailableReason());
                    }
                }
                yield new Hours(Attendance.INCLUDED, null, run.getAttendanceAt(), riders,
                        unreadable, false);
            }
        };
    }

    /** The delivery counts a computation uses, and where they came from. */
    private record Delivered(Deliveries source, String note, Instant readAt,
                             Map<String, Integer> riders, boolean fresh) {
    }

    /**
     * A live count of every order each rider delivered, or — when Order Manager cannot say — the
     * note that the ledger stands in. Called before any transaction opens, and always stamped: it is
     * the moment the run's figures were read.
     */
    private Delivered readDelivered(String company, PayPeriods.Period period, String bearer) {
        Instant at = now();
        DeliveriesRead read = deliveriesSource.fleet(bearer, company, zone, period.from(),
                period.to());
        return read.available()
                ? new Delivered(Deliveries.ORDERS, null, at, read.riders(), true)
                : new Delivered(Deliveries.LEDGER, read.reason(), at, Map.of(), true);
    }

    /** The count a draft already holds. Never a live read. */
    private Delivered storedDelivered(CarrierPayRun run) {
        if (run.getDeliveries() != Deliveries.ORDERS) {
            return new Delivered(Deliveries.LEDGER, run.getDeliveriesNote(), run.getDeliveriesAt(),
                    Map.of(), false);
        }
        Map<String, Integer> riders = new HashMap<>();
        for (CarrierPayDelivered row : deliveredCopies.findByRunId(run.getId())) {
            riders.put(row.getRiderRef(), row.getDelivered());
        }
        return new Delivered(Deliveries.ORDERS, null, run.getDeliveriesAt(), riders, false);
    }

    /**
     * Whether a run's figures were last read before its period ended. Deliveries are counted, and
     * hours judged, as they stood at the read, so whatever came after is missing from them.
     */
    private boolean readBeforeItEnded(CarrierPayRun run) {
        Instant read = run.getDeliveriesAt();
        return read == null || read.isBefore(periodOf(run).endIn(zone));
    }

    /**
     * Pay per delivery, counted from the ledger: a delivery that earned no fee is missing from the
     * count, so whoever approves has to say they approve without it.
     */
    private static boolean deliveriesUncounted(CarrierPayRun run, CarrierPayPolicy policy) {
        return run.getDeliveries() != Deliveries.ORDERS
                && policy.terms().perDeliveryRate().signum() > 0;
    }

    private record Computation(CarrierPayPolicy policy, Hours hours, Delivered delivered,
                               List<PayslipCalculator.Payslip> payslips) {
    }

    /**
     * A period's payslips: the deliveries and hours given, and the ledger's facts as they are now —
     * the company's tips in the period, the cash its riders collected by its end and still hold, its
     * corrections still unpaid.
     */
    private Computation compute(String company, UUID runId, CarrierPayPolicy policy,
                                PayPeriods.Period period, Hours hours, Delivered delivered,
                                List<CarrierPayLine> named) {
        Instant from = period.startIn(zone);
        Instant to = period.endIn(zone);

        Map<String, Integer> deliveries = new HashMap<>();
        if (delivered.source() == Deliveries.ORDERS) {
            deliveries.putAll(delivered.riders());
        } else {
            // Standing in, counted afresh each time: every row is a delivery, not every delivery a row.
            for (RiderLedgerEntry job : riderLedger.jobsForCarrierBetween(company, from, to)) {
                deliveries.merge(job.getRiderRef(), 1, Integer::sum);
            }
        }
        Map<String, BigDecimal> tips = new HashMap<>();
        for (RiderLedgerEntry tip : riderLedger.tipsForCarrierBetween(company, from, to)) {
            tips.merge(tip.getRiderRef(), tip.getAmount(), BigDecimal::add);
        }

        List<PayslipCalculator.Payslip> slips = PayslipCalculator.compute(
                new PayslipCalculator.Inputs(policy.terms(), hours.status(), deliveries, tips,
                        // Cash of the period and before, still held: riders keep collecting after
                        // the period ends, and none of that may move a figure being approved.
                        hours.riders(), carrierCash.heldByRider(company, to), named,
                        pendingCorrections(company, runId, period)));
        return new Computation(policy, hours, delivered, slips);
    }

    /** Corrections to runs of earlier periods, not yet paid in any run. */
    private List<CarrierPayAdjustment> pendingCorrections(String company, UUID runId,
                                                          PayPeriods.Period period) {
        List<CarrierPayAdjustment> pending =
                adjustments.findByCarrierRefAndAppliedRunIdIsNullOrderByCreatedAtAsc(company);
        if (pending.isEmpty()) {
            return List.of();
        }
        Map<UUID, CarrierPayRun> corrected = new HashMap<>();
        for (CarrierPayRun run : runs.findAllById(pending.stream()
                .map(CarrierPayAdjustment::getCorrectsRunId)
                .collect(Collectors.toSet()))) {
            corrected.put(run.getId(), run);
        }
        return pending.stream()
                .filter(correction -> {
                    CarrierPayRun run = corrected.get(correction.getCorrectsRunId());
                    return run != null && !run.getId().equals(runId)
                            && run.getPeriodTo().isBefore(period.from());
                })
                .toList();
    }

    /**
     * A draft recomputed after an edit: the ledger's facts now, and the hours and deliveries it
     * already holds.
     */
    private void refigure(String company, CarrierPayRun run, List<CarrierPayLine> named,
                          Instant now) {
        CarrierPayPolicy policy = policyFor(company, run);
        replaceFigures(run, compute(company, run.getId(), policy, periodOf(run),
                storedHours(run, policy.terms()), storedDelivered(run), named), now);
    }

    /**
     * Replaces a draft's payslips, computed lines and — from a fresh read — its hours and
     * deliveries.
     */
    private void replaceFigures(CarrierPayRun run, Computation computed, Instant now) {
        UUID id = run.getId();
        Hours hours = computed.hours();
        Delivered delivered = computed.delivered();

        payslips.deleteByRunId(id);
        lines.deleteByRunIdAndSourceIn(id, EnumSet.of(Source.COMPUTED, Source.ADJUSTMENT));
        if (hours.fresh() || hours.status() != Attendance.INCLUDED) {
            snapshots.deleteByRunId(id);
        }
        if (delivered.fresh()) {
            deliveredCopies.deleteByRunId(id);
        }
        // Flushed before the inserts: a flush runs its inserts first, and the new rows take the old
        // ones' (run, rider) keys.
        payslips.flush();

        if (hours.fresh() && hours.status() == Attendance.INCLUDED) {
            List<CarrierPayAttendance> copies = new ArrayList<>();
            hours.riders().entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .forEach(e -> copies.add(CarrierPayAttendance.of(id, e.getKey(),
                            e.getValue().workedSeconds(), e.getValue().manualSeconds(),
                            e.getValue().overtimeSeconds(), e.getValue().lates(),
                            e.getValue().absences())));
            // Kept with no figures, so an edit or the approval still knows why they are unknown.
            hours.unreadable().entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .forEach(e -> copies.add(
                            CarrierPayAttendance.unreadable(id, e.getKey(), e.getValue())));
            snapshots.saveAll(copies);
        }
        if (delivered.fresh() && delivered.source() == Deliveries.ORDERS) {
            deliveredCopies.saveAll(delivered.riders().entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .map(e -> CarrierPayDelivered.of(id, e.getKey(), e.getValue()))
                    .toList());
        }
        List<CarrierPayslip> slips = new ArrayList<>();
        List<CarrierPayLine> generated = new ArrayList<>();
        for (PayslipCalculator.Payslip payslip : computed.payslips()) {
            slips.add(CarrierPayslip.draft(id, payslip.riderRef(), payslip.figures()));
            for (PayslipCalculator.Line line : payslip.lines()) {
                generated.add(line.adjustment() == null
                        ? CarrierPayLine.computed(id, payslip.riderRef(), line.kind(),
                                line.quantity(), line.rate(), line.amount(), now)
                        : CarrierPayLine.adjustment(id, line.adjustment(), now));
            }
        }
        payslips.saveAll(slips);
        lines.saveAll(generated);
        run.recomputed(computed.policy().getId(), hours.status(), hours.note(), hours.readAt(),
                delivered.source(), delivered.note(), delivered.readAt(), now);
    }

    /** Whether a fresh computation says exactly what the draft already says. */
    private static boolean unchanged(CarrierPayRun run, List<CarrierPayslip> stored,
                                     List<CarrierPayLine> storedLines, Computation fresh) {
        if (!run.getPolicyId().equals(fresh.policy().getId())
                || run.getAttendance() != fresh.hours().status()
                || run.getDeliveries() != fresh.delivered().source()
                || stored.size() != fresh.payslips().size()) {
            return false;
        }
        Map<String, CarrierPayslip.Figures> byRider = new HashMap<>();
        stored.forEach(slip -> byRider.put(slip.getRiderRef(), slip.figures()));
        for (PayslipCalculator.Payslip slip : fresh.payslips()) {
            if (!slip.figures().sameAs(byRider.get(slip.riderRef()))) {
                return false;
            }
        }
        Set<UUID> carried = storedLines.stream()
                .filter(l -> l.getSource() == Source.ADJUSTMENT)
                .map(CarrierPayLine::getAdjustmentId)
                .collect(Collectors.toSet());
        Set<UUID> carrying = fresh.payslips().stream()
                .flatMap(p -> p.lines().stream())
                .filter(l -> l.adjustment() != null)
                .map(l -> l.adjustment().getId())
                .collect(Collectors.toSet());
        return carried.equals(carrying);
    }

    /**
     * The rules in force on a run's first day, provided they still cut its days into the same
     * period — a draft left behind by a change of calendar cannot be recomputed or approved.
     */
    private CarrierPayPolicy policyFor(String company, CarrierPayRun run) {
        CarrierPayPolicy policy = PayPeriods.inForce(versions(company), run.getPeriodFrom())
                .orElseThrow(() -> refusal(409, "NO_POLICY", "No pay rules cover this period."));
        if (!PayPeriods.containing(run.getPeriodFrom(), policy.getPayCycle())
                .equals(periodOf(run))) {
            throw refusal(409, "PERIOD_CHANGED", "Your pay rules now pay these days in a "
                    + "different period. Discard this draft and start that period instead.");
        }
        return policy;
    }

    private static String summary(CarrierPayRun run, Computation computed) {
        Hours hours = computed.hours();
        Delivered delivered = computed.delivered();
        return "revision " + run.getRevision() + "; " + computed.payslips().size()
                + " payslips; hours " + hours.status()
                + (hours.note() == null ? "" : " (" + hours.note() + ")")
                + "; deliveries " + delivered.source()
                + (delivered.note() == null ? "" : " (" + delivered.note() + ")");
    }

    // ------------------------------------------------------------------------------- plumbing

    private CarrierPayRun draftOf(String company, UUID runId) {
        CarrierPayRun run = runs.findByIdAndCarrierRef(runId, company)
                .orElseThrow(CarrierPayrollService::notFound);
        requireDraft(run);
        return run;
    }

    private CarrierPayRun lockDraft(String company, UUID runId) {
        CarrierPayRun run = runs.lockOwned(runId, company)
                .orElseThrow(CarrierPayrollService::notFound);
        requireDraft(run);
        return run;
    }

    private CarrierPayRun lockApproved(String company, UUID runId) {
        CarrierPayRun run = runs.lockOwned(runId, company)
                .orElseThrow(CarrierPayrollService::notFound);
        if (run.isDraft()) {
            throw refusal(409, "NOT_APPROVED",
                    "Approve this pay run before recording payments or corrections.");
        }
        return run;
    }

    private static void requireDraft(CarrierPayRun run) {
        if (!run.isDraft()) {
            throw refusal(409, "NOT_DRAFT", "This pay run is approved and its payslips are "
                    + "final. Add a correction instead.");
        }
    }

    /** Only a rider already on the run: the one way a line or correction can name a rider. */
    private void requireOnRun(CarrierPayRun run, String riderRef) {
        boolean onRun = riderRef != null && payslips.findByRunIdOrderByRiderRefAsc(run.getId())
                .stream()
                .anyMatch(slip -> slip.getRiderRef().equals(riderRef));
        if (!onRun) {
            throw refusal(404, "RIDER_NOT_ON_RUN", "That rider has no payslip on this pay run.");
        }
    }

    private static CarrierPayslip payslipOf(List<CarrierPayslip> slips, UUID payslipId) {
        return slips.stream()
                .filter(slip -> slip.getId().equals(payslipId))
                .findFirst()
                .orElseThrow(() -> refusal(404, "PAYSLIP_NOT_FOUND",
                        "That payslip is not on this pay run."));
    }

    private List<CarrierPayLine> liveNamedLines(CarrierPayRun run) {
        return lines.findByRunIdAndSourceAndRemovedAtIsNull(run.getId(), Source.MANUAL);
    }

    private void settleIfDone(CarrierPayRun run, List<CarrierPayslip> slips, String actor,
                              Instant now) {
        if (run.getStatus() == Status.APPROVED
                && slips.stream().noneMatch(CarrierPayslip::isOutstanding)) {
            run.paid(now);
            record(run, null, Action.RUN_PAID, actor, null);
        }
    }

    private void record(CarrierPayRun run, String riderRef, Action action, String actor,
                        String detail) {
        events.save(CarrierPayrollEvent.of(run.getCarrierRef(), run.getId(), riderRef, action,
                actor, detail, now()));
    }

    private static String paid(CarrierPayslip slip, CashFloatEntry.Method how, String ref) {
        return slip.getNet().toPlainString() + " by " + how + (ref == null ? "" : ", ref " + ref);
    }

    private static PayPeriods.Period periodOf(CarrierPayRun run) {
        return new PayPeriods.Period(run.getPeriodFrom(), run.getPeriodTo());
    }

    private record RunData(CarrierPayRun run, CarrierPayPolicy policy, boolean aligned,
                           List<CarrierPayslip> slips, List<CarrierPayLine> lines,
                           List<CarrierPayAdjustment> corrections,
                           List<CarrierPayrollEvent> history, long jobsSinceComputed,
                           Map<String, String> unreadableHours) {
    }

    private RunData load(CarrierPayRun run) {
        CarrierPayPolicy policy = policies.findById(run.getPolicyId())
                .orElseThrow(() -> new IllegalStateException(
                        "Pay run " + run.getId() + " names rules that do not exist"));
        PayPeriods.Period period = periodOf(run);
        boolean aligned = PayPeriods.periodOf(versions(run.getCarrierRef()), run.getPeriodFrom())
                .map(period::equals)
                .orElse(false);
        return new RunData(run, policy, aligned,
                payslips.findByRunIdOrderByRiderRefAsc(run.getId()),
                lines.findByRunIdOrderByCreatedAtAsc(run.getId()),
                adjustments.findByCorrectsRunIdOrderByCreatedAtAsc(run.getId()),
                events.findByRunIdOrderByOccurredAtDesc(run.getId(), PageRequest.of(0, HISTORY)),
                // Only a count taken from the ledger can miss a job that reached the ledger late.
                run.getDeliveries() == Deliveries.LEDGER
                        ? riderLedger.countJobsForCarrierRecordedAfter(run.getCarrierRef(),
                                period.startIn(zone), period.endIn(zone), run.getComputedAt())
                        : 0L,
                unreadableHours(run));
    }

    /** The riders whose own figures a run's attendance read did not believe, with why. */
    private Map<String, String> unreadableHours(CarrierPayRun run) {
        if (run.getAttendance() != Attendance.INCLUDED) {
            return Map.of();
        }
        Map<String, String> out = new HashMap<>();
        for (CarrierPayAttendance row : snapshots.findByRunId(run.getId())) {
            if (!row.isReadable()) {
                out.put(row.getRiderRef(), row.getUnavailableReason());
            }
        }
        return out;
    }

    /**
     * Why one rider's hours are unknown. The whole read failed or was never made — its reason; this
     * rider's own figures were not believed; or attendance listed no time of theirs with the company
     * in the period. Figures are clipped to each rider's time on the fleet, so a rider who joined or
     * left mid-period is listed with their part — one who is not listed at all has no time with the
     * company that attendance knows of.
     */
    private static String hoursReason(CarrierPayRun run, Map<String, String> unreadable,
                                      String riderRef) {
        if (run.getAttendance() != Attendance.INCLUDED) {
            return run.getAttendanceNote() == null ? "NOT_READ" : run.getAttendanceNote();
        }
        return unreadable.getOrDefault(riderRef, "NOT_LISTED");
    }

    /** Names are resolved outside the read transaction: a Keycloak lookup holds no connection. */
    private RunView render(RunData d) {
        CarrierPayRun run = d.run();
        boolean needsHours = d.policy().terms().needsAttendance();

        Map<String, List<LineView>> linesByRider = new LinkedHashMap<>();
        d.lines().stream()
                .filter(line -> !line.isRemoved())
                .sorted(Comparator.comparingInt((CarrierPayLine line) -> line.getKind().ordinal())
                        .thenComparing(CarrierPayLine::getCreatedAt))
                .forEach(line -> linesByRider
                        .computeIfAbsent(line.getRiderRef(), rider -> new ArrayList<>())
                        .add(new LineView(line, line.getSource() == Source.COMPUTED
                                ? null
                                : nameOf(line.getCreatedBy()))));

        List<PayslipView> slips = d.slips().stream()
                .map(slip -> {
                    boolean unknown = needsHours && slip.figures().workedSeconds() == null;
                    return new PayslipView(slip, nameOf(slip.getRiderRef()),
                            List.copyOf(linesByRider.getOrDefault(slip.getRiderRef(), List.of())),
                            unknown,
                            unknown ? hoursReason(run, d.unreadableHours(), slip.getRiderRef())
                                    : null,
                            nameOf(slip.getPaidBy()), nameOf(slip.getFailedBy()));
                })
                .sorted(Comparator.comparing((PayslipView v) -> v.name() == null)
                        .thenComparing(v -> v.name() == null ? "" : v.name(),
                                String.CASE_INSENSITIVE_ORDER)
                        .thenComparing(v -> v.slip().getRiderRef()))
                .toList();

        boolean hoursMissing = needsHours && (run.getAttendance() != Attendance.INCLUDED
                || slips.stream().anyMatch(PayslipView::hoursUnknown));
        boolean periodOver = today().isAfter(run.getPeriodTo());
        List<MissingHours> missing = slips.stream()
                .filter(PayslipView::hoursUnknown)
                .map(v -> new MissingHours(v.slip().getRiderRef(), v.name(), v.hoursReason()))
                .toList();
        return new RunView(run, policyView(d.policy()), nameOf(run.getApprovedBy()), slips,
                totals(d.slips()),
                d.corrections().stream()
                        .map(c -> new CorrectionView(c, nameOf(c.getRiderRef()),
                                nameOf(c.getCreatedBy())))
                        .toList(),
                d.history().stream()
                        .map(e -> new EventView(e, nameOf(e.getActor()), nameOf(e.getRiderRef())))
                        .toList(),
                periodOver, d.jobsSinceComputed(),
                run.isDraft() && (hoursMissing || deliveriesUncounted(run, d.policy()))
                        && !slips.isEmpty(),
                run.isDraft() && !d.aligned(),
                run.isDraft() && periodOver && readBeforeItEnded(run),
                missing);
    }

    static Totals totals(List<CarrierPayslip> slips) {
        BigDecimal payable = ZERO;
        BigDecimal owed = ZERO;
        BigDecimal gross = ZERO;
        BigDecimal bonuses = ZERO;
        BigDecimal deductions = ZERO;
        BigDecimal tips = ZERO;
        BigDecimal netted = ZERO;
        BigDecimal paid = ZERO;
        BigDecimal outstanding = ZERO;
        int due = 0;
        int failed = 0;
        int paidCount = 0;
        for (CarrierPayslip slip : slips) {
            CarrierPayslip.Figures f = slip.figures();
            if (f.net().signum() > 0) {
                payable = payable.add(f.net());
            } else {
                owed = owed.add(f.net().negate());
            }
            gross = gross.add(f.gross());
            bonuses = bonuses.add(f.bonuses());
            deductions = deductions.add(f.deductions());
            tips = tips.add(f.tips());
            netted = netted.add(f.cashNetted());
            switch (slip.getStatus()) {
                case PAID -> {
                    paid = paid.add(f.net());
                    paidCount++;
                }
                case DUE -> {
                    outstanding = outstanding.add(f.net());
                    due++;
                }
                case FAILED -> {
                    outstanding = outstanding.add(f.net());
                    failed++;
                }
                default -> {
                }
            }
        }
        BigDecimal average = slips.isEmpty()
                ? null
                : payable.divide(BigDecimal.valueOf(slips.size()), 2, RoundingMode.HALF_UP);
        return new Totals(slips.size(), money(payable), average, money(gross), money(bonuses),
                money(deductions), money(owed), money(tips), money(netted), money(paid),
                money(outstanding), due, failed, paidCount);
    }

    private static CarrierPayLine.Kind named(CarrierPayLine.Kind kind) {
        if (kind != CarrierPayLine.Kind.BONUS && kind != CarrierPayLine.Kind.DEDUCTION) {
            throw refusal(400, "BAD_KIND", "A line is a BONUS or a DEDUCTION.");
        }
        return kind;
    }

    /** An amount a person typed: to the cent, not negative, and not absurd. */
    static BigDecimal amount(BigDecimal value, boolean zeroAllowed) {
        if (value == null || value.signum() < 0 || (!zeroAllowed && value.signum() == 0)
                || value.stripTrailingZeros().scale() > 2 || value.compareTo(MAX_AMOUNT) > 0) {
            throw refusal(400, "BAD_AMOUNT", "Amounts are " + (zeroAllowed ? "0 or more" : "more than 0")
                    + ", to the cent, and at most " + MAX_AMOUNT.toPlainString() + ".");
        }
        return value.setScale(2, RoundingMode.UNNECESSARY);
    }

    private static BigDecimal multiplier(BigDecimal value) {
        if (value == null || value.compareTo(BigDecimal.ONE) < 0
                || value.compareTo(MAX_MULTIPLIER) > 0 || value.stripTrailingZeros().scale() > 2) {
            throw refusal(400, "BAD_MULTIPLIER",
                    "The overtime multiplier is between 1.00 and 5.00.");
        }
        return value.setScale(2, RoundingMode.UNNECESSARY);
    }

    private static String text(String value, int max, String message) {
        String trimmed = value == null ? "" : value.trim();
        if (trimmed.isEmpty() || trimmed.length() > max) {
            throw refusal(400, "BAD_TEXT", message);
        }
        return trimmed;
    }

    private static String optionalText(String value, int max, String message) {
        return value == null || value.isBlank() ? null : text(value, max, message);
    }

    private static CashFloatEntry.Method payoutMethod(CashFloatEntry.Method method) {
        if (method == null || method == CashFloatEntry.Method.PAYROLL_DEDUCTION) {
            throw refusal(400, "BAD_METHOD",
                    "Say how the rider was paid: CASH, BANK_DEPOSIT or WALLET.");
        }
        return method;
    }

    private static BigDecimal money(BigDecimal amount) {
        return (amount == null ? BigDecimal.ZERO : amount).setScale(2, RoundingMode.HALF_UP);
    }

    /** A person's display name from Keycloak, or null. Never the raw id dressed up as a name. */
    private String nameOf(String subject) {
        if (subject == null) {
            return null;
        }
        String name = accounts.profileOf(subject).name();
        return name == null || name.isBlank() ? null : name;
    }
}
