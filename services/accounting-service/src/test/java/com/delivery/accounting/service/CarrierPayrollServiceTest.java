package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyIterable;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.assertj.core.api.ThrowableAssert.ThrowingCallable;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.transaction.PlatformTransactionManager;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CarrierPayAdjustment;
import com.delivery.accounting.domain.CarrierPayAdjustmentRepository;
import com.delivery.accounting.domain.CarrierPayAttendance;
import com.delivery.accounting.domain.CarrierPayAttendanceRepository;
import com.delivery.accounting.domain.CarrierPayDelivered;
import com.delivery.accounting.domain.CarrierPayDeliveredRepository;
import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayLine.Kind;
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
import com.delivery.accounting.domain.CashFloatEntry.Method;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.service.CarrierPayrollService.Approval;
import com.delivery.accounting.service.CarrierPayrollService.ApprovalOutcome;
import com.delivery.accounting.service.CarrierPayrollService.PayrollRefusal;
import com.delivery.accounting.service.CarrierPayrollService.PayslipView;
import com.delivery.accounting.service.CarrierPayrollService.RunView;
import com.delivery.accounting.service.PayslipCalculator.RiderHours;
import com.delivery.accounting.service.RiderAttendanceSource.AttendanceRead;
import com.delivery.accounting.service.RiderDeliveriesSource.DeliveriesRead;

/**
 * A delivery company's pay runs, from rules to recorded payment.
 *
 * <p>The repositories are in-memory lists behind mocks, so each test walks the real service through a
 * whole lifecycle and reads back what it would have stored. What is proved: a run's figures are what
 * its approver saw (hours included, which are a copy and never re-read); approval nets a rider's
 * cash through the custody model once, under a key the run and the rider decide; nothing about an
 * approved run changes afterwards; payments and corrections go forward only; and nothing here is
 * ever the platform's money.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("a delivery company's pay runs")
class CarrierPayrollServiceTest {

    private static final String COMPANY = "provider-77";
    private static final String RIVAL = "provider-rival";
    private static final String STAFF = "carrier-staff-sub";
    private static final String TOKEN = "caller-token";
    private static final String YOUSSEF = "rider-youssef";
    private static final String RANIA = "rider-rania";
    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");
    private static final LocalDate OCT_1 = LocalDate.parse("2026-10-01");
    private static final LocalDate OCT_15 = LocalDate.parse("2026-10-15");
    private static final LocalDate OCT_16 = LocalDate.parse("2026-10-16");
    /** Midnight into the 16th in Beirut: where October's first half ends. */
    private static final Instant FIRST_HALF_ENDS = Instant.parse("2026-10-15T21:00:00Z");

    @Mock
    private CarrierPayPolicyRepository policies;
    @Mock
    private CarrierPayRunRepository runs;
    @Mock
    private CarrierPayslipRepository payslips;
    @Mock
    private CarrierPayLineRepository lines;
    @Mock
    private CarrierPayAdjustmentRepository adjustments;
    @Mock
    private CarrierPayAttendanceRepository snapshots;
    @Mock
    private CarrierPayDeliveredRepository deliveredCopies;
    @Mock
    private CarrierPayrollEventRepository events;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private CarrierCashService carrierCash;
    @Mock
    private CashFloatService cashFloat;
    @Mock
    private RiderAttendanceSource attendance;
    @Mock
    private RiderDeliveriesSource deliveriesSource;
    @Mock
    private AccountDirectory accounts;
    @Mock
    private PlatformTransactionManager transactionManager;

    /** "Now" is the 20th of October, at noon in Beirut: the first half is over, the second is not. */
    private final MovableClock clock = new MovableClock(Instant.parse("2026-10-20T09:00:00Z"));
    private CarrierPayrollService service;

    private final List<CarrierPayPolicy> policyRows = new ArrayList<>();
    private final Map<UUID, CarrierPayRun> runRows = new LinkedHashMap<>();
    private final List<CarrierPayslip> slipRows = new ArrayList<>();
    private final List<CarrierPayLine> lineRows = new ArrayList<>();
    private final List<CarrierPayAdjustment> adjustmentRows = new ArrayList<>();
    private final List<CarrierPayAttendance> snapshotRows = new ArrayList<>();
    private final List<CarrierPayDelivered> deliveredRows = new ArrayList<>();
    private final List<CarrierPayrollEvent> eventRows = new ArrayList<>();
    private final List<RiderLedgerEntry> ledgerRows = new ArrayList<>();
    /** Cash riders took at doors for the company and still hold, each with when they took it. */
    private final List<Collected> collections = new ArrayList<>();
    private AttendanceRead read = AttendanceRead.unavailable("NOT_DEPLOYED");
    /** Every order the company's riders delivered, as Order Manager holds them: fee or none. */
    private final List<Delivery> deliveredOrders = new ArrayList<>();
    /** A reason, to make Order Manager's count unavailable; null while it answers. */
    private String ordersUnavailable;

    private static final Map<String, String> NAMES = Map.of(
            YOUSSEF, "Youssef Kanaan", RANIA, "Rania Ghandour", STAFF, "Kamal M.");

    @BeforeEach
    void setUp() {
        service = new CarrierPayrollService(policies, runs, payslips, lines, adjustments, snapshots,
                deliveredCopies, events, riderLedger, carrierCash, cashFloat, attendance,
                deliveriesSource, accounts, transactionManager, "Asia/Beirut", "USD", clock);

        when(policies.findByCarrierRefOrderByEffectiveFromDescCreatedAtDesc(COMPANY))
                .thenAnswer(i -> policyRows.stream()
                        .sorted(Comparator.comparing(CarrierPayPolicy::getEffectiveFrom)
                                .thenComparing(CarrierPayPolicy::getCreatedAt)
                                .reversed())
                        .toList());
        when(policies.findById(any())).thenAnswer(i -> policyRows.stream()
                .filter(p -> p.getId().equals(i.getArgument(0)))
                .findFirst());
        when(policies.save(any(CarrierPayPolicy.class))).thenAnswer(i -> {
            policyRows.add(i.getArgument(0));
            return i.getArgument(0);
        });

        when(runs.save(any(CarrierPayRun.class))).thenAnswer(i -> {
            CarrierPayRun run = i.getArgument(0);
            runRows.put(run.getId(), run);
            return run;
        });
        when(runs.findByIdAndCarrierRef(any(), anyString()))
                .thenAnswer(i -> owned(i.getArgument(0), i.getArgument(1)));
        when(runs.lockOwned(any(), anyString()))
                .thenAnswer(i -> owned(i.getArgument(0), i.getArgument(1)));
        when(runs.overlapping(anyString(), any(), any())).thenAnswer(i -> runRows.values().stream()
                .filter(r -> r.getCarrierRef().equals(i.getArgument(0))
                        && !r.getPeriodFrom().isAfter(i.<LocalDate>getArgument(2))
                        && !r.getPeriodTo().isBefore(i.<LocalDate>getArgument(1)))
                .toList());
        when(runs.endingOnOrAfter(anyString(), any())).thenAnswer(i -> runRows.values().stream()
                .filter(r -> r.getCarrierRef().equals(i.getArgument(0))
                        && !r.getPeriodTo().isBefore(i.<LocalDate>getArgument(1)))
                .sorted(Comparator.comparing(CarrierPayRun::getPeriodFrom).reversed())
                .toList());
        when(runs.findFirstByCarrierRefAndStatusNotOrderByPeriodFromDesc(anyString(), any()))
                .thenAnswer(i -> runRows.values().stream()
                        .filter(r -> r.getCarrierRef().equals(i.getArgument(0))
                                && r.getStatus() != i.<Status>getArgument(1))
                        .max(Comparator.comparing(CarrierPayRun::getPeriodFrom)));
        when(runs.findAllById(any())).thenAnswer(i -> {
            List<CarrierPayRun> out = new ArrayList<>();
            i.<Iterable<UUID>>getArgument(0).forEach(id -> {
                if (runRows.containsKey(id)) {
                    out.add(runRows.get(id));
                }
            });
            return out;
        });
        doAnswer(i -> runRows.remove(i.<CarrierPayRun>getArgument(0).getId()))
                .when(runs).delete(any(CarrierPayRun.class));

        when(payslips.findByRunIdOrderByRiderRefAsc(any())).thenAnswer(i -> slipRows.stream()
                .filter(p -> p.getRunId().equals(i.getArgument(0)))
                .sorted(Comparator.comparing(CarrierPayslip::getRiderRef))
                .toList());
        when(payslips.findByRunIdIn(any())).thenAnswer(i -> slipRows.stream()
                .filter(p -> i.<Collection<UUID>>getArgument(0).contains(p.getRunId()))
                .toList());
        when(payslips.saveAll(anyIterable())).thenAnswer(i -> {
            List<CarrierPayslip> in = new ArrayList<>();
            i.<Iterable<CarrierPayslip>>getArgument(0).forEach(in::add);
            slipRows.addAll(in);
            return in;
        });
        doAnswer(i -> slipRows.removeIf(p -> p.getRunId().equals(i.getArgument(0))))
                .when(payslips).deleteByRunId(any());

        when(lines.findByRunIdOrderByCreatedAtAsc(any())).thenAnswer(i -> lineRows.stream()
                .filter(l -> l.getRunId().equals(i.getArgument(0)))
                .toList());
        when(lines.findByRunIdAndSourceAndRemovedAtIsNull(any(), any()))
                .thenAnswer(i -> lineRows.stream()
                        .filter(l -> l.getRunId().equals(i.getArgument(0))
                                && l.getSource() == i.<Source>getArgument(1) && !l.isRemoved())
                        .toList());
        when(lines.findByIdAndRunId(any(), any())).thenAnswer(i -> lineRows.stream()
                .filter(l -> l.getId().equals(i.getArgument(0))
                        && l.getRunId().equals(i.getArgument(1)))
                .findFirst());
        when(lines.save(any(CarrierPayLine.class))).thenAnswer(i -> {
            lineRows.add(i.getArgument(0));
            return i.getArgument(0);
        });
        when(lines.saveAll(anyIterable())).thenAnswer(i -> {
            List<CarrierPayLine> in = new ArrayList<>();
            i.<Iterable<CarrierPayLine>>getArgument(0).forEach(in::add);
            lineRows.addAll(in);
            return in;
        });
        doAnswer(i -> lineRows.removeIf(l -> l.getRunId().equals(i.getArgument(0))
                && i.<Collection<Source>>getArgument(1).contains(l.getSource())))
                .when(lines).deleteByRunIdAndSourceIn(any(), any());
        doAnswer(i -> lineRows.removeIf(l -> l.getRunId().equals(i.getArgument(0))))
                .when(lines).deleteByRunId(any());

        when(adjustments.findByCarrierRefAndAppliedRunIdIsNullOrderByCreatedAtAsc(anyString()))
                .thenAnswer(i -> adjustmentRows.stream()
                        .filter(a -> a.getCarrierRef().equals(i.getArgument(0)) && a.isPending())
                        .toList());
        when(adjustments.findByCorrectsRunIdOrderByCreatedAtAsc(any()))
                .thenAnswer(i -> adjustmentRows.stream()
                        .filter(a -> a.getCorrectsRunId().equals(i.getArgument(0)))
                        .toList());
        when(adjustments.lockAll(any())).thenAnswer(i -> adjustmentRows.stream()
                .filter(a -> i.<Collection<UUID>>getArgument(0).contains(a.getId()))
                .toList());
        when(adjustments.save(any(CarrierPayAdjustment.class))).thenAnswer(i -> {
            adjustmentRows.add(i.getArgument(0));
            return i.getArgument(0);
        });

        when(snapshots.findByRunId(any())).thenAnswer(i -> snapshotRows.stream()
                .filter(s -> s.getRunId().equals(i.getArgument(0)))
                .toList());
        when(snapshots.saveAll(anyIterable())).thenAnswer(i -> {
            List<CarrierPayAttendance> in = new ArrayList<>();
            i.<Iterable<CarrierPayAttendance>>getArgument(0).forEach(in::add);
            snapshotRows.addAll(in);
            return in;
        });
        doAnswer(i -> snapshotRows.removeIf(s -> s.getRunId().equals(i.getArgument(0))))
                .when(snapshots).deleteByRunId(any());

        when(deliveredCopies.findByRunId(any())).thenAnswer(i -> deliveredRows.stream()
                .filter(r -> r.getRunId().equals(i.getArgument(0)))
                .toList());
        when(deliveredCopies.saveAll(anyIterable())).thenAnswer(i -> {
            List<CarrierPayDelivered> in = new ArrayList<>();
            i.<Iterable<CarrierPayDelivered>>getArgument(0).forEach(in::add);
            deliveredRows.addAll(in);
            return in;
        });
        doAnswer(i -> deliveredRows.removeIf(r -> r.getRunId().equals(i.getArgument(0))))
                .when(deliveredCopies).deleteByRunId(any());

        when(events.save(any(CarrierPayrollEvent.class))).thenAnswer(i -> {
            eventRows.add(i.getArgument(0));
            return i.getArgument(0);
        });
        when(events.findByRunIdOrderByOccurredAtDesc(any(), any())).thenAnswer(i -> eventRows
                .stream()
                .filter(e -> i.getArgument(0).equals(e.getRunId()))
                .toList());

        when(riderLedger.jobsForCarrierBetween(eq(COMPANY), any(), any()))
                .thenAnswer(i -> ledger(RiderLedgerEntry.EntryType.JOB_EARNING,
                        i.getArgument(1), i.getArgument(2)));
        when(riderLedger.tipsForCarrierBetween(eq(COMPANY), any(), any()))
                .thenAnswer(i -> ledger(RiderLedgerEntry.EntryType.TIP,
                        i.getArgument(1), i.getArgument(2)));
        when(riderLedger.countJobsForCarrierRecordedAfter(anyString(), any(), any(), any()))
                .thenReturn(0L);

        when(carrierCash.heldByRider(eq(COMPANY), any())).thenAnswer(i -> {
            Map<String, BigDecimal> held = new LinkedHashMap<>();
            collections.stream()
                    .filter(c -> c.at().isBefore(i.<Instant>getArgument(1)))
                    .forEach(c -> held.merge(c.rider(), c.amount(), BigDecimal::add));
            return held;
        });
        // A real deduction clears what the rider took before its cut-off; this one does too, so
        // later reads agree.
        when(cashFloat.handOver(anyString(), anyString(), any(), any(), any())).thenAnswer(i -> {
            collections.removeIf(c -> c.rider().equals(i.getArgument(1))
                    && c.at().isBefore(i.<Instant>getArgument(4)));
            return new CashFloatService.Handover(UUID.randomUUID(), i.getArgument(1),
                    i.getArgument(0), i.getArgument(2), 2, Method.PAYROLL_DEDUCTION, null, STAFF,
                    Instant.now(), false);
        });
        when(attendance.fleet(anyString(), anyString(), any(), any(), any()))
                .thenAnswer(i -> read);
        // Order Manager counts the orders delivered in the period's days that have happened so far.
        when(deliveriesSource.fleet(anyString(), anyString(), any(), any(), any())).thenAnswer(i -> {
            if (ordersUnavailable != null) {
                return DeliveriesRead.unavailable(ordersUnavailable);
            }
            Instant from = i.<LocalDate>getArgument(3).atStartOfDay(BEIRUT).toInstant();
            Instant to = i.<LocalDate>getArgument(4).plusDays(1).atStartOfDay(BEIRUT).toInstant();
            Map<String, Integer> counts = new HashMap<>();
            deliveredOrders.stream()
                    .filter(d -> !d.at().isBefore(from) && d.at().isBefore(to)
                            && !d.at().isAfter(clock.instant()))
                    .forEach(d -> counts.merge(d.rider(), 1, Integer::sum));
            return DeliveriesRead.of(counts);
        });
        when(accounts.profileOf(anyString())).thenAnswer(i ->
                new AccountDirectory.Profile("ACC-1", NAMES.get(i.<String>getArgument(0)), null));
    }

    // ----------------------------------------------------------------------------- the helpers

    private Optional<CarrierPayRun> owned(UUID id, String carrier) {
        CarrierPayRun run = runRows.get(id);
        return run != null && run.getCarrierRef().equals(carrier) ? Optional.of(run) : Optional.empty();
    }

    private List<RiderLedgerEntry> ledger(RiderLedgerEntry.EntryType type, Instant from, Instant to) {
        return ledgerRows.stream()
                .filter(e -> e.getEntryType() == type
                        && !e.getEarnedAt().isBefore(from) && e.getEarnedAt().isBefore(to))
                .toList();
    }

    private static CarrierPayPolicy.Terms terms(String perDelivery, String hourly) {
        return new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, new BigDecimal(perDelivery),
                hourly == null ? null : new BigDecimal(hourly), true, new BigDecimal("1.00"),
                new BigDecimal("0.00"), new BigDecimal("0.00"));
    }

    /** Rules already on file, saved before anything in the test happens. */
    private void rules(String from, PayCycle cycle, String perDelivery, String hourly) {
        CarrierPayPolicy.Terms t = terms(perDelivery, hourly);
        policyRows.add(CarrierPayPolicy.version(COMPANY, LocalDate.parse(from),
                new CarrierPayPolicy.Terms(cycle, t.perDeliveryRate(), t.hourlyRate(),
                        t.payManualHours(), t.overtimeMultiplier(), t.lateDeduction(),
                        t.absenceDeduction()),
                "USD", STAFF, Instant.parse("2026-08-01T00:00:00Z").plusSeconds(policyRows.size())));
    }

    /** A job for the company, delivered at noon in Beirut on {@code day}. */
    private void delivered(String rider, String day) {
        deliveredAt(rider, LocalDate.parse(day).atTime(12, 0).atZone(BEIRUT).toInstant());
    }

    private record Collected(String rider, BigDecimal amount, Instant at) {
    }

    /** Cash {@code rider} took at a door for the company at noon in Beirut on {@code day}. */
    private void holds(String rider, String amount, String day) {
        collections.add(new Collected(rider, new BigDecimal(amount),
                LocalDate.parse(day).atTime(12, 0).atZone(BEIRUT).toInstant()));
    }

    /** A job that earned a fee: Order Manager has the order, and the ledger what it earned. */
    private void deliveredAt(String rider, Instant at) {
        deliveredOrders.add(new Delivery(rider, at));
        ledgerRows.add(RiderLedgerEntry.jobEarning(rider, UUID.randomUUID(), new BigDecimal("1.50"),
                "USD", RiderLedgerEntry.Fleet.CARRIER, COMPANY, "customer-1", at));
    }

    private record Delivery(String rider, Instant at) {
    }

    /**
     * A free delivery at noon in Beirut on {@code day}: Order Manager has the order, and the ledger has
     * nothing, because a job that earned no fee writes no JOB_EARNING row.
     */
    private void deliveredFree(String rider, String day) {
        deliveredOrders.add(new Delivery(rider,
                LocalDate.parse(day).atTime(12, 0).atZone(BEIRUT).toInstant()));
    }

    private static PayslipView slip(RunView run, String rider) {
        return run.payslips().stream()
                .filter(p -> p.slip().getRiderRef().equals(rider))
                .findFirst()
                .orElseThrow(() -> new AssertionError(rider + " has no payslip"));
    }

    private static void assertRefused(ThrowingCallable call, int status, String code) {
        assertThatThrownBy(call).isInstanceOfSatisfying(PayrollRefusal.class, refusal -> {
            assertThat(refusal.code()).isEqualTo(code);
            assertThat(refusal.status()).isEqualTo(status);
        });
    }

    /** Youssef with two deliveries and Rania with one, in October's first half, approved. */
    private RunView approvedFirstHalf() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        delivered(YOUSSEF, "2026-10-06");
        delivered(RANIA, "2026-10-07");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        Approval approval = service.approve(COMPANY, run.run().getId(), run.run().getRevision(),
                false, STAFF);
        assertThat(approval.outcome()).isEqualTo(ApprovalOutcome.APPROVED);
        return approval.run();
    }

    // ------------------------------------------------------------------------------- the rules

    @Test
    @DisplayName("new rules start on the first day of a pay period, and a change of calendar on the 1st")
    void rulesStartOnAPeriodStart() {
        assertRefused(() -> service.setPolicy(COMPANY, LocalDate.parse("2026-10-20"),
                terms("2.00", null), STAFF), 400, "NOT_A_PERIOD_START");

        CarrierPayrollService.PolicyView saved =
                service.setPolicy(COMPANY, OCT_16, terms("2.00", null), STAFF);
        assertThat(saved.policy().getEffectiveFrom()).isEqualTo(OCT_16);
        assertThat(saved.createdByName()).isEqualTo("Kamal M.");
        assertThat(eventRows).extracting(CarrierPayrollEvent::getAction)
                .containsExactly(Action.POLICY_SET);

        policyRows.clear();
        rules("2026-09-01", PayCycle.MONTHLY, "2.00", null);
        assertRefused(() -> service.setPolicy(COMPANY, LocalDate.parse("2026-11-16"),
                terms("2.00", null), STAFF), 400, "CALENDAR_CHANGE_NOT_ON_THE_FIRST");
        assertThat(service.setPolicy(COMPANY, LocalDate.parse("2026-11-01"), terms("2.00", null),
                STAFF).policy().getPayCycle()).isEqualTo(PayCycle.SEMI_MONTHLY);
    }

    @Test
    @DisplayName("amounts are to the cent and the overtime multiplier stays between 1 and 5")
    void ruleAmounts() {
        assertRefused(() -> service.setPolicy(COMPANY, OCT_16, terms("2.005", null), STAFF),
                400, "BAD_AMOUNT");
        assertRefused(() -> service.setPolicy(COMPANY, OCT_16, terms("-1.00", null), STAFF),
                400, "BAD_AMOUNT");
        for (String multiplier : List.of("0.90", "5.01")) {
            CarrierPayPolicy.Terms t = new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY,
                    new BigDecimal("2.00"), null, true, new BigDecimal(multiplier),
                    new BigDecimal("0.00"), new BigDecimal("0.00"));
            assertRefused(() -> service.setPolicy(COMPANY, OCT_16, t, STAFF), 400, "BAD_MULTIPLIER");
        }
        assertThat(policyRows).isEmpty();
    }

    @Test
    @DisplayName("new rules never reach back into a period whose run is approved")
    void rulesStayOutOfApprovedPeriods() {
        approvedFirstHalf();

        assertRefused(() -> service.setPolicy(COMPANY, OCT_1, terms("9.00", null), STAFF),
                409, "PERIOD_APPROVED");
        assertThat(service.policy(COMPANY).startOptions().get(PayCycle.SEMI_MONTHLY))
                .first().isEqualTo(OCT_16);
        assertThat(service.setPolicy(COMPANY, OCT_16, terms("3.00", null), STAFF).policy()
                .getEffectiveFrom()).isEqualTo(OCT_16);
    }

    // -------------------------------------------------------------------------------- the runs

    @Test
    @DisplayName("a run needs rules for its period, starts on its first day, and is one per period")
    void startingARun() {
        assertRefused(() -> service.start(COMPANY, OCT_1, STAFF, TOKEN), 409, "NO_POLICY");
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        assertRefused(() -> service.start(COMPANY, LocalDate.parse("2026-10-05"), STAFF, TOKEN),
                400, "NOT_A_PERIOD_START");
        assertRefused(() -> service.start(COMPANY, LocalDate.parse("2026-11-01"), STAFF, TOKEN),
                400, "FUTURE_PERIOD");

        // The last minute of the 15th in Beirut is the first half's; the first of the 16th is not.
        deliveredAt(YOUSSEF, Instant.parse("2026-10-15T20:59:00Z"));
        deliveredAt(RANIA, Instant.parse("2026-10-15T21:00:00Z"));
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);

        assertThat(run.run().getStatus()).isEqualTo(Status.DRAFT);
        assertThat(run.run().getRevision()).isEqualTo(1);
        assertThat(run.run().getPeriodTo()).isEqualTo(OCT_15);
        assertThat(run.payslips()).singleElement().satisfies(p -> {
            assertThat(p.name()).isEqualTo("Youssef Kanaan");
            assertThat(p.slip().getNet()).isEqualByComparingTo("2.00");
        });
        assertThat(eventRows).extracting(CarrierPayrollEvent::getAction)
                .containsExactly(Action.RUN_STARTED);

        assertThatThrownBy(() -> service.start(COMPANY, OCT_1, STAFF, TOKEN))
                .isInstanceOfSatisfying(PayrollRefusal.class, refusal -> {
                    assertThat(refusal.code()).isEqualTo("RUN_EXISTS");
                    assertThat(refusal.detail()).isEqualTo(run.run().getId());
                });
        // Rules paying by the delivery alone never ask attendance anything.
        verifyNoInteractions(attendance);
        assertThat(run.run().getAttendance()).isEqualTo(Attendance.NOT_NEEDED);
    }

    @Test
    @DisplayName("the hours a draft uses are copied into it when read, and only a recompute reads them again")
    void hoursAreASnapshot() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", "4.00");
        read = AttendanceRead.of(Map.of(
                YOUSSEF, new RiderHours(36_000, 0, 0, 0, 0),
                RANIA, new RiderHours(0, 0, 0, 1, 0)));
        delivered(YOUSSEF, "2026-10-03");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        assertThat(run.run().getAttendance()).isEqualTo(Attendance.INCLUDED);
        assertThat(run.run().getAttendanceAt()).isEqualTo(Instant.parse("2026-10-20T09:00:00Z"));
        // Every rider the read listed is copied: Rania has no pay yet, but a late delivery could.
        assertThat(snapshotRows).extracting(CarrierPayAttendance::getRiderRef)
                .containsExactlyInAnyOrder(YOUSSEF, RANIA);
        assertThat(slip(run, YOUSSEF).slip().figures().basePay()).isEqualByComparingTo("40.00");

        // Order-tracking's October moves after October; an edit to the draft does not follow it.
        read = AttendanceRead.of(Map.of(YOUSSEF, new RiderHours(72_000, 0, 0, 0, 0)));
        clock.set("2026-10-21T09:00:00Z");
        RunView edited = service.addLine(COMPANY, id, YOUSSEF, Kind.BONUS, "Eid bonus",
                new BigDecimal("25.00"), STAFF);
        assertThat(slip(edited, YOUSSEF).slip().figures().basePay()).isEqualByComparingTo("40.00");
        assertThat(slip(edited, YOUSSEF).slip().getBonuses()).isEqualByComparingTo("25.00");
        assertThat(edited.run().getAttendanceAt()).isEqualTo(Instant.parse("2026-10-20T09:00:00Z"));
        verify(attendance, times(1)).fleet(anyString(), anyString(), any(), any(), any());

        RunView recomputed = service.recompute(COMPANY, id, STAFF, TOKEN);
        assertThat(slip(recomputed, YOUSSEF).slip().figures().basePay())
                .isEqualByComparingTo("80.00");
        assertThat(slip(recomputed, YOUSSEF).slip().getBonuses()).isEqualByComparingTo("25.00");
        assertThat(recomputed.run().getAttendanceAt())
                .isEqualTo(Instant.parse("2026-10-21T09:00:00Z"));
        verify(attendance, times(2)).fleet(TOKEN, COMPANY, BEIRUT, OCT_1, OCT_15);
        assertThat(snapshotRows).extracting(CarrierPayAttendance::getRiderRef)
                .containsExactly(YOUSSEF);
    }

    @Test
    @DisplayName("hours that could not be read are said on the run, and approving without them is acknowledged")
    void missingHours() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", "4.00");
        read = AttendanceRead.unavailable("NOT_DEPLOYED");
        delivered(YOUSSEF, "2026-10-03");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        assertThat(run.run().getAttendance()).isEqualTo(Attendance.UNAVAILABLE);
        assertThat(run.run().getAttendanceNote()).isEqualTo("NOT_DEPLOYED");
        assertThat(run.needsAcknowledgement()).isTrue();
        assertThat(slip(run, YOUSSEF).hoursUnknown()).isTrue();
        assertThat(run.hoursMissingFor()).singleElement().satisfies(m -> {
            assertThat(m.name()).isEqualTo("Youssef Kanaan");
            assertThat(m.reason()).isEqualTo("NOT_DEPLOYED");
        });
        assertThat(slip(run, YOUSSEF).slip().getNet()).isEqualByComparingTo("2.00");

        Approval unacknowledged = service.approve(COMPANY, id, 1, false, STAFF);
        assertThat(unacknowledged.outcome()).isEqualTo(ApprovalOutcome.NEEDS_ACKNOWLEDGEMENT);
        assertThat(unacknowledged.run().run().getStatus()).isEqualTo(Status.DRAFT);

        assertThat(service.approve(COMPANY, id, 1, true, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
        // Approval never reads attendance: the approved hours are the ones the approver saw.
        verify(attendance, times(1)).fleet(anyString(), anyString(), any(), any(), any());
    }

    /**
     * Attendance is read for the whole fleet at once, but a figure that cannot be believed is one
     * rider's problem: that rider's hours are unknown and named at approval, and everyone else is
     * paid theirs.
     */
    @Test
    @DisplayName("one rider's unreadable hours are that rider's alone: named for the approver, and everyone else is paid")
    void oneRidersHoursUnreadable() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", "4.00");
        read = AttendanceRead.of(Map.of(YOUSSEF, new RiderHours(36_000, 0, 0, 0, 0)),
                Map.of(RANIA, "UNREADABLE"));
        delivered(YOUSSEF, "2026-10-03");
        delivered(RANIA, "2026-10-04");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        assertThat(run.run().getAttendance()).isEqualTo(Attendance.INCLUDED);
        assertThat(slip(run, YOUSSEF).hoursUnknown()).isFalse();
        assertThat(slip(run, YOUSSEF).slip().figures().basePay()).isEqualByComparingTo("40.00");
        assertThat(slip(run, RANIA).hoursUnknown()).isTrue();
        assertThat(slip(run, RANIA).hoursReason()).isEqualTo("UNREADABLE");
        assertThat(slip(run, RANIA).slip().getNet()).isEqualByComparingTo("2.00");
        assertThat(run.hoursMissingFor()).singleElement().satisfies(m -> {
            assertThat(m.riderRef()).isEqualTo(RANIA);
            assertThat(m.name()).isEqualTo("Rania Ghandour");
            assertThat(m.reason()).isEqualTo("UNREADABLE");
        });
        assertThat(run.needsAcknowledgement()).isTrue();

        // An edit reads the copy, which still knows why Rania's hours are unknown.
        RunView edited = service.addLine(COMPANY, id, YOUSSEF, Kind.BONUS, "Eid bonus",
                new BigDecimal("5.00"), STAFF);
        assertThat(edited.hoursMissingFor()).extracting(CarrierPayrollService.MissingHours::reason)
                .containsExactly("UNREADABLE");
        assertThat(slip(edited, YOUSSEF).slip().figures().basePay()).isEqualByComparingTo("40.00");
        verify(attendance, times(1)).fleet(anyString(), anyString(), any(), any(), any());

        assertThat(service.approve(COMPANY, id, 2, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.NEEDS_ACKNOWLEDGEMENT);
        assertThat(service.approve(COMPANY, id, 2, true, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
    }

    /**
     * Order-tracking clips every figure to the rider's time on the company's fleet, so a rider who
     * joined on the 9th is listed with their hours from the 9th, and one who left keeps theirs up to
     * the day they left. Payroll pays exactly what it is given and adds nothing for the move. A rider
     * on the run whom attendance does not list has no time with the company it knows of: their hours
     * are unknown, and they are named as not listed.
     */
    @Test
    @DisplayName("a rider on the fleet for part of the period is paid the part attendance gives; one it does not list is named")
    void partOfThePeriod() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", "4.00");
        // Rania joined on the 9th: the company's figures for her start there — five hours.
        read = AttendanceRead.of(Map.of(RANIA, new RiderHours(18_000, 0, 0, 0, 0)));
        delivered(RANIA, "2026-10-10");
        delivered(YOUSSEF, "2026-10-03");

        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);

        verify(attendance, times(1)).fleet(TOKEN, COMPANY, BEIRUT, OCT_1, OCT_15);
        assertThat(slip(run, RANIA).hoursUnknown()).isFalse();
        assertThat(slip(run, RANIA).slip().figures().workedSeconds()).isEqualTo(18_000L);
        assertThat(slip(run, RANIA).slip().figures().basePay()).isEqualByComparingTo("20.00");
        assertThat(slip(run, YOUSSEF).hoursUnknown()).isTrue();
        assertThat(slip(run, YOUSSEF).hoursReason()).isEqualTo("NOT_LISTED");
        assertThat(run.hoursMissingFor()).extracting(CarrierPayrollService.MissingHours::riderRef)
                .containsExactly(YOUSSEF);
    }

    @Test
    @DisplayName("a period is approved only once it is over, and an empty one not at all")
    void whatCannotBeApproved() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-17");
        RunView open = service.start(COMPANY, OCT_16, STAFF, TOKEN);
        assertRefused(() -> service.approve(COMPANY, open.run().getId(), 1, false, STAFF),
                409, "PERIOD_OPEN");

        RunView empty = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        assertThat(empty.payslips()).isEmpty();
        assertRefused(() -> service.approve(COMPANY, empty.run().getId(), 1, false, STAFF),
                409, "EMPTY_RUN");
    }

    // --------------------------------------------------------------------------- the approval

    @Test
    @DisplayName("approving nets cash the pay covers through the custody model, once, under a key from the run and the rider")
    void approvalNetsCash() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        for (int i = 0; i < 50; i++) {
            delivered(YOUSSEF, "2026-10-05");
        }
        delivered(RANIA, "2026-10-06");
        holds(YOUSSEF, "60.00", "2026-10-05");
        // More than her pay: left in her bag for the hub to collect, not deducted in part.
        holds(RANIA, "30.00", "2026-10-06");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        Approval approval = service.approve(COMPANY, id, 1, false, STAFF);

        assertThat(approval.outcome()).isEqualTo(ApprovalOutcome.APPROVED);
        ArgumentCaptor<CashFloatEntry.Recorded> recorded =
                ArgumentCaptor.forClass(CashFloatEntry.Recorded.class);
        verify(cashFloat).handOver(eq(COMPANY), eq(YOUSSEF),
                argThat(amount -> amount.compareTo(new BigDecimal("60.00")) == 0),
                recorded.capture(), eq(FIRST_HALF_ENDS));
        verify(cashFloat, never()).handOver(anyString(), eq(RANIA), any(), any(), any());
        assertThat(recorded.getValue().by()).isEqualTo(STAFF);
        assertThat(recorded.getValue().method()).isEqualTo(Method.PAYROLL_DEDUCTION);
        assertThat(recorded.getValue().requestKey())
                .isEqualTo(CarrierPayrollService.payrollKey(id, YOUSSEF))
                .matches("^[A-Za-z0-9_-]{8,64}$");

        PayslipView youssef = slip(approval.run(), YOUSSEF);
        assertThat(youssef.slip().getStatus()).isEqualTo(CarrierPayslip.Status.DUE);
        assertThat(youssef.slip().getHandoverId()).isNotNull();
        assertThat(youssef.slip().getNet()).isEqualByComparingTo("40.00");
        assertThat(slip(approval.run(), RANIA).slip().getCashNetted()).isEqualByComparingTo("0.00");
        assertThat(approval.run().run().getStatus()).isEqualTo(Status.APPROVED);
        assertThat(approval.run().approvedByName()).isEqualTo("Kamal M.");
        assertThat(eventRows).extracting(CarrierPayrollEvent::getAction)
                .contains(Action.CASH_NETTED, Action.RUN_APPROVED);

        // Pressed again: already approved, and the cash is not taken a second time.
        assertThat(service.approve(COMPANY, id, 1, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.ALREADY_APPROVED);
        verify(cashFloat, times(1)).handOver(anyString(), anyString(), any(), any(), any());
    }

    @Test
    @DisplayName("the deduction key is the same for the same run and rider, and different for any other")
    void deductionKeys() {
        UUID run = UUID.randomUUID();
        assertThat(CarrierPayrollService.payrollKey(run, YOUSSEF))
                .isEqualTo(CarrierPayrollService.payrollKey(run, YOUSSEF))
                .hasSize(40);
        assertThat(CarrierPayrollService.payrollKey(run, RANIA))
                .isNotEqualTo(CarrierPayrollService.payrollKey(run, YOUSSEF));
        assertThat(CarrierPayrollService.payrollKey(UUID.randomUUID(), YOUSSEF))
                .isNotEqualTo(CarrierPayrollService.payrollKey(run, YOUSSEF));
    }

    @Test
    @DisplayName("counted from the ledger, figures that moved since the approver looked are recomputed, not approved")
    void figuresMoved() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        ordersUnavailable = "UNREACHABLE";
        delivered(YOUSSEF, "2026-10-05");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();
        // A delivery from the 14th reaches the ledger late.
        delivered(YOUSSEF, "2026-10-14");

        Approval moved = service.approve(COMPANY, id, 1, true, STAFF);
        assertThat(moved.outcome()).isEqualTo(ApprovalOutcome.FIGURES_CHANGED);
        assertThat(moved.run().run().getStatus()).isEqualTo(Status.DRAFT);
        assertThat(moved.run().run().getRevision()).isEqualTo(2);
        assertThat(slip(moved.run(), YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");

        // A page still showing revision 1 is told to look again; revision 2 is approved.
        assertThat(service.approve(COMPANY, id, 1, true, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.FIGURES_CHANGED);
        assertThat(service.approve(COMPANY, id, 2, true, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
        verifyNoInteractions(cashFloat);
    }

    @Test
    @DisplayName("cash that moved at the last moment approves nothing")
    void cashMovedAtTheLastMoment() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        for (int i = 0; i < 50; i++) {
            delivered(YOUSSEF, "2026-10-05");
        }
        holds(YOUSSEF, "60.00", "2026-10-05");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();
        doThrow(new CashFloatService.AmountChangedException(new BigDecimal("75.00")))
                .when(cashFloat).handOver(anyString(), anyString(), any(), any(), any());

        assertThatThrownBy(() -> service.approve(COMPANY, id, 1, false, STAFF))
                .isInstanceOf(CashFloatService.AmountChangedException.class);

        assertThat(runRows.get(id).getStatus()).isEqualTo(Status.DRAFT);
        assertThat(slipRows).allSatisfy(p ->
                assertThat(p.getStatus()).isEqualTo(CarrierPayslip.Status.DRAFT));
    }

    /**
     * Riders keep working after a period ends, and every cash delivery grows what they hold. Only
     * what they took by the period's end is the run's: later cash may not move a figure the approver
     * is looking at, or approval would be refused all through the working day.
     */
    @Test
    @DisplayName("cash riders take after the period ends moves nothing on it, and stays in their bags")
    void cashCollectedAfterThePeriod() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        for (int i = 0; i < 50; i++) {
            delivered(YOUSSEF, "2026-10-05");
        }
        delivered(RANIA, "2026-10-06");
        holds(YOUSSEF, "60.00", "2026-10-14");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        // While the approver reads the draft on the 20th, both riders take cash at doors.
        holds(YOUSSEF, "35.00", "2026-10-20");
        holds(RANIA, "12.00", "2026-10-20");

        Approval approval = service.approve(COMPANY, id, 1, false, STAFF);

        assertThat(approval.outcome()).isEqualTo(ApprovalOutcome.APPROVED);
        verify(cashFloat).handOver(eq(COMPANY), eq(YOUSSEF),
                argThat(amount -> amount.compareTo(new BigDecimal("60.00")) == 0), any(),
                eq(FIRST_HALF_ENDS));
        PayslipView youssef = slip(approval.run(), YOUSSEF);
        assertThat(youssef.slip().figures().cashHeld()).isEqualByComparingTo("60.00");
        assertThat(youssef.slip().getNet()).isEqualByComparingTo("40.00");
        assertThat(slip(approval.run(), RANIA).slip().figures().cashHeld())
                .isEqualByComparingTo("0.00");
        // What they took on the 20th is still theirs to hand over, at the hub or in the next run.
        assertThat(collections).extracting(Collected::amount)
                .containsExactlyInAnyOrder(new BigDecimal("35.00"), new BigDecimal("12.00"));
    }

    @Test
    @DisplayName("the period's cash handed over at the hub before approval is a change the approver sees")
    void periodCashHandedOverAtTheHub() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        for (int i = 0; i < 50; i++) {
            delivered(YOUSSEF, "2026-10-05");
        }
        holds(YOUSSEF, "60.00", "2026-10-14");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        assertThat(slip(run, YOUSSEF).slip().getNet()).isEqualByComparingTo("40.00");

        // The hub takes Youssef's bag on the 20th, before anyone approves.
        collections.clear();

        Approval moved = service.approve(COMPANY, run.run().getId(), 1, false, STAFF);
        assertThat(moved.outcome()).isEqualTo(ApprovalOutcome.FIGURES_CHANGED);
        assertThat(slip(moved.run(), YOUSSEF).slip().getNet()).isEqualByComparingTo("100.00");
        verifyNoInteractions(cashFloat);
    }

    @Test
    @DisplayName("rules changed mid-period reprice a draft, and never an approved run")
    void rulesChangedMidPeriod() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        delivered(YOUSSEF, "2026-10-12");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();
        assertThat(slip(run, YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");

        // On the 20th the company raises the rate for the period still in draft.
        service.setPolicy(COMPANY, OCT_1, terms("3.00", null), STAFF);
        Approval repriced = service.approve(COMPANY, id, 1, false, STAFF);
        assertThat(repriced.outcome()).isEqualTo(ApprovalOutcome.FIGURES_CHANGED);
        assertThat(slip(repriced.run(), YOUSSEF).slip().getNet()).isEqualByComparingTo("6.00");
        assertThat(service.approve(COMPANY, id, 2, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
        UUID approvedUnder = runRows.get(id).getPolicyId();

        // New rules for the next period leave the approved run as it was.
        service.setPolicy(COMPANY, OCT_16, terms("4.00", null), STAFF);
        RunView after = service.run(COMPANY, id).orElseThrow();
        assertThat(after.run().getPolicyId()).isEqualTo(approvedUnder);
        assertThat(after.policy().policy().terms().perDeliveryRate()).isEqualByComparingTo("3.00");
        assertThat(slip(after, YOUSSEF).slip().getNet()).isEqualByComparingTo("6.00");
        assertRefused(() -> service.recompute(COMPANY, id, STAFF, TOKEN), 409, "NOT_DRAFT");
        assertRefused(() -> service.addLine(COMPANY, id, YOUSSEF, Kind.BONUS, "Late bonus",
                new BigDecimal("5.00"), STAFF), 409, "NOT_DRAFT");
        assertRefused(() -> service.discard(COMPANY, id, STAFF), 409, "NOT_DRAFT");
    }

    // --------------------------------------------------------------------------- deliveries

    /**
     * A rider paid per delivery is paid for every order they delivered. A free delivery earns the
     * company no fee, so the ledger never wrote it a JOB_EARNING row: counting rows would skip it.
     */
    @Test
    @DisplayName("a free delivery is a delivery: counted from the company's orders and paid like any other")
    void freeDeliveriesArePaid() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        deliveredFree(YOUSSEF, "2026-10-06");
        deliveredFree(RANIA, "2026-10-07");
        // Late ledger rows say nothing about a count taken from orders.
        when(riderLedger.countJobsForCarrierRecordedAfter(anyString(), any(), any(), any()))
                .thenReturn(5L);

        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);

        verify(deliveriesSource).fleet(TOKEN, COMPANY, BEIRUT, OCT_1, OCT_15);
        assertThat(run.run().getDeliveries()).isEqualTo(Deliveries.ORDERS);
        assertThat(run.run().getDeliveriesAt()).isEqualTo(Instant.parse("2026-10-20T09:00:00Z"));
        assertThat(slip(run, YOUSSEF).slip().figures().deliveries()).isEqualTo(2);
        assertThat(slip(run, YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");
        // Rania delivered only free orders, and is paid for them.
        assertThat(slip(run, RANIA).slip().getNet()).isEqualByComparingTo("2.00");
        assertThat(run.needsAcknowledgement()).isFalse();
        assertThat(run.jobsSinceComputed()).isZero();
        assertThat(deliveredRows).extracting(CarrierPayDelivered::getRiderRef)
                .containsExactlyInAnyOrder(YOUSSEF, RANIA);

        // Approving reads the copy the approver saw, never Order Manager again.
        assertThat(service.approve(COMPANY, run.run().getId(), 1, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
        verify(deliveriesSource, times(1)).fleet(anyString(), anyString(), any(), any(), any());
    }

    @Test
    @DisplayName("when orders cannot be counted the ledger stands in, the run says so, and approving it is acknowledged")
    void deliveriesFromTheLedger() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        ordersUnavailable = "NOT_DEPLOYED";
        delivered(YOUSSEF, "2026-10-05");
        deliveredFree(YOUSSEF, "2026-10-06");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();

        assertThat(run.run().getDeliveries()).isEqualTo(Deliveries.LEDGER);
        assertThat(run.run().getDeliveriesNote()).isEqualTo("NOT_DEPLOYED");
        // The ledger knows only the job that earned a fee: a floor, not the count.
        assertThat(slip(run, YOUSSEF).slip().getNet()).isEqualByComparingTo("2.00");
        assertThat(run.needsAcknowledgement()).isTrue();
        assertThat(deliveredRows).isEmpty();
        assertThat(service.approve(COMPANY, id, 1, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.NEEDS_ACKNOWLEDGEMENT);

        // Order Manager answers again: a recompute counts every delivery and leaves nothing to say.
        ordersUnavailable = null;
        RunView recomputed = service.recompute(COMPANY, id, STAFF, TOKEN);
        assertThat(recomputed.run().getDeliveries()).isEqualTo(Deliveries.ORDERS);
        assertThat(recomputed.run().getDeliveriesNote()).isNull();
        assertThat(slip(recomputed, YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");
        assertThat(recomputed.needsAcknowledgement()).isFalse();
        assertThat(service.approve(COMPANY, id, 2, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
    }

    /**
     * A copy stops at the moment it is taken. A draft started while its period was running holds the
     * deliveries up to then; approved as it stood, the rest of the period would go unpaid.
     */
    @Test
    @DisplayName("a draft last read before its period ended is recomputed before it can be approved")
    void readBeforeThePeriodEnded() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        clock.set("2026-10-10T09:00:00Z");
        delivered(YOUSSEF, "2026-10-05");
        RunView early = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = early.run().getId();
        assertThat(early.readBeforePeriodEnd()).isFalse();

        // Youssef keeps delivering until the period ends; the draft's copy stops on the 10th.
        delivered(YOUSSEF, "2026-10-13");
        clock.set("2026-10-20T09:00:00Z");
        RunView stale = service.run(COMPANY, id).orElseThrow();
        assertThat(stale.readBeforePeriodEnd()).isTrue();
        assertThat(slip(stale, YOUSSEF).slip().getNet()).isEqualByComparingTo("2.00");
        assertRefused(() -> service.approve(COMPANY, id, 1, true, STAFF), 409, "RECOMPUTE_NEEDED");
        assertThat(runRows.get(id).getStatus()).isEqualTo(Status.DRAFT);

        RunView fresh = service.recompute(COMPANY, id, STAFF, TOKEN);
        assertThat(fresh.readBeforePeriodEnd()).isFalse();
        assertThat(slip(fresh, YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");
        assertThat(service.approve(COMPANY, id, 2, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
    }

    // ----------------------------------------------------------------------------- payments

    @Test
    @DisplayName("a payment is recorded once, and the run is paid when the last one due is")
    void payments() {
        RunView run = approvedFirstHalf();
        UUID id = run.run().getId();
        UUID youssef = slip(run, YOUSSEF).slip().getId();
        UUID rania = slip(run, RANIA).slip().getId();

        assertRefused(() -> service.markPaid(COMPANY, id, youssef, Method.PAYROLL_DEDUCTION, null,
                STAFF), 400, "BAD_METHOD");
        assertRefused(() -> service.markPaid(COMPANY, id, UUID.randomUUID(), Method.CASH, null,
                STAFF), 404, "PAYSLIP_NOT_FOUND");

        RunView one = service.markPaid(COMPANY, id, youssef, Method.BANK_DEPOSIT, "TRX-1", STAFF);
        assertThat(slip(one, YOUSSEF).slip().getStatus()).isEqualTo(CarrierPayslip.Status.PAID);
        assertThat(slip(one, YOUSSEF).slip().getPaidReference()).isEqualTo("TRX-1");
        assertThat(slip(one, YOUSSEF).paidByName()).isEqualTo("Kamal M.");
        assertThat(one.run().getStatus()).isEqualTo(Status.APPROVED);

        int recorded = eventRows.size();
        service.markPaid(COMPANY, id, youssef, Method.CASH, null, STAFF);
        assertThat(eventRows).hasSize(recorded);
        assertThat(slip(service.run(COMPANY, id).orElseThrow(), YOUSSEF).slip().getPaidMethod())
                .isEqualTo(Method.BANK_DEPOSIT);

        RunView paid = service.markPaid(COMPANY, id, rania, Method.CASH, null, STAFF);
        assertThat(paid.run().getStatus()).isEqualTo(Status.PAID);
        assertThat(paid.totals().paid()).isEqualByComparingTo("6.00");
        assertThat(eventRows).extracting(CarrierPayrollEvent::getAction).contains(Action.RUN_PAID);
    }

    @Test
    @DisplayName("a failed payment needs a reason and stays owed; a recorded payment cannot fail")
    void failedPayments() {
        RunView run = approvedFirstHalf();
        UUID id = run.run().getId();
        UUID youssef = slip(run, YOUSSEF).slip().getId();

        assertRefused(() -> service.markFailed(COMPANY, id, youssef, "  ", STAFF), 400, "BAD_TEXT");
        RunView failed = service.markFailed(COMPANY, id, youssef, "Wrong account number", STAFF);
        assertThat(slip(failed, YOUSSEF).slip().getStatus()).isEqualTo(CarrierPayslip.Status.FAILED);
        assertThat(failed.totals().failed()).isEqualTo(1);
        assertThat(failed.totals().outstanding()).isEqualByComparingTo("6.00");

        service.markPaid(COMPANY, id, youssef, Method.WALLET, null, STAFF);
        assertRefused(() -> service.markFailed(COMPANY, id, youssef, "Bounced", STAFF),
                409, "ALREADY_PAID");
    }

    @Test
    @DisplayName("paying everything waiting refuses a total that moved, and leaves failed payments alone")
    void payAll() {
        RunView run = approvedFirstHalf();
        UUID id = run.run().getId();
        service.markFailed(COMPANY, id, slip(run, RANIA).slip().getId(), "Unreachable", STAFF);

        assertThatThrownBy(() -> service.payAll(COMPANY, id, new BigDecimal("6.00"), Method.CASH,
                null, STAFF))
                .isInstanceOfSatisfying(PayrollRefusal.class, refusal -> {
                    assertThat(refusal.code()).isEqualTo("TOTAL_CHANGED");
                    assertThat((BigDecimal) refusal.detail()).isEqualByComparingTo("4.00");
                });

        RunView paid = service.payAll(COMPANY, id, new BigDecimal("4.00"), Method.CASH, "Hub",
                STAFF);
        assertThat(slip(paid, YOUSSEF).slip().getStatus()).isEqualTo(CarrierPayslip.Status.PAID);
        assertThat(slip(paid, RANIA).slip().getStatus()).isEqualTo(CarrierPayslip.Status.FAILED);
        assertThat(paid.run().getStatus()).isEqualTo(Status.APPROVED);
        assertRefused(() -> service.payAll(COMPANY, id, new BigDecimal("0.00"), Method.CASH, null,
                STAFF), 409, "NOTHING_DUE");
    }

    @Test
    @DisplayName("a deduction bigger than the pay leaves a negative net that is owed, never paid")
    void negativeNet() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        delivered(RANIA, "2026-10-06");
        RunView run = service.start(COMPANY, OCT_1, STAFF, TOKEN);
        UUID id = run.run().getId();
        RunView edited = service.addLine(COMPANY, id, RANIA, Kind.DEDUCTION, "Lost helmet",
                new BigDecimal("10.00"), STAFF);
        assertThat(slip(edited, RANIA).slip().getNet()).isEqualByComparingTo("-8.00");
        assertThat(edited.totals().payable()).isEqualByComparingTo("2.00");
        assertThat(edited.totals().owedByRiders()).isEqualByComparingTo("8.00");
        assertThat(edited.totals().average()).isEqualByComparingTo("1.00");

        RunView approved = service.approve(COMPANY, id, edited.run().getRevision(), false, STAFF).run();
        UUID rania = slip(approved, RANIA).slip().getId();
        assertThat(slip(approved, RANIA).slip().getStatus())
                .isEqualTo(CarrierPayslip.Status.NOTHING_DUE);
        assertRefused(() -> service.markPaid(COMPANY, id, rania, Method.CASH, null, STAFF),
                409, "NOTHING_DUE");
        RunView paid = service.markPaid(COMPANY, id, slip(approved, YOUSSEF).slip().getId(),
                Method.CASH, null, STAFF);
        assertThat(paid.run().getStatus()).isEqualTo(Status.PAID);
    }

    // --------------------------------------------------------------------------- corrections

    @Test
    @DisplayName("a correction to an approved run is paid in the rider's next run, once")
    void corrections() {
        RunView first = approvedFirstHalf();
        UUID firstId = first.run().getId();

        assertRefused(() -> service.addCorrection(COMPANY, firstId, "rider-stranger", Kind.BONUS,
                new BigDecimal("6.00"), "Missed jobs", STAFF), 404, "RIDER_NOT_ON_RUN");
        RunView corrected = service.addCorrection(COMPANY, firstId, YOUSSEF, Kind.BONUS,
                new BigDecimal("6.00"), "Two jobs missed on the 14th", STAFF);
        assertThat(corrected.corrections()).singleElement()
                .satisfies(c -> assertThat(c.adjustment().isPending()).isTrue());
        assertThat(slip(corrected, YOUSSEF).slip().getNet()).isEqualByComparingTo("4.00");

        // The next period: Youssef did nothing in it and is still paid the correction.
        clock.set("2026-11-02T09:00:00Z");
        RunView second = service.start(COMPANY, OCT_16, STAFF, TOKEN);
        UUID secondId = second.run().getId();
        assertThat(second.payslips()).singleElement().satisfies(p -> {
            assertThat(p.slip().getRiderRef()).isEqualTo(YOUSSEF);
            assertThat(p.slip().getNet()).isEqualByComparingTo("6.00");
            assertThat(p.lines()).singleElement()
                    .satisfies(l -> assertThat(l.line().getSource()).isEqualTo(Source.ADJUSTMENT));
        });
        assertRefused(() -> service.addCorrection(COMPANY, secondId, YOUSSEF, Kind.BONUS,
                new BigDecimal("1.00"), "Draft", STAFF), 409, "NOT_APPROVED");

        assertThat(service.approve(COMPANY, secondId, 1, false, STAFF).outcome())
                .isEqualTo(ApprovalOutcome.APPROVED);
        assertThat(adjustmentRows.get(0).getAppliedRunId()).isEqualTo(secondId);

        // Paid once: the run after does not carry it again.
        clock.set("2026-11-17T09:00:00Z");
        delivered(RANIA, "2026-11-03");
        assertThat(service.start(COMPANY, LocalDate.parse("2026-11-01"), STAFF, TOKEN).payslips())
                .extracting(p -> p.slip().getRiderRef())
                .containsExactly(RANIA);
    }

    // -------------------------------------------------------------------- scope and the books

    @Test
    @DisplayName("another company's run is not found, whatever is asked of it")
    void anotherCompanysRun() {
        RunView run = approvedFirstHalf();
        UUID id = run.run().getId();
        UUID payslip = slip(run, YOUSSEF).slip().getId();

        assertThat(service.run(RIVAL, id)).isEmpty();
        assertRefused(() -> service.approve(RIVAL, id, 1, true, STAFF), 404, "RUN_NOT_FOUND");
        assertRefused(() -> service.markPaid(RIVAL, id, payslip, Method.CASH, null, STAFF),
                404, "RUN_NOT_FOUND");
        assertRefused(() -> service.payAll(RIVAL, id, new BigDecimal("6.00"), Method.CASH, null,
                STAFF), 404, "RUN_NOT_FOUND");
        assertRefused(() -> service.addCorrection(RIVAL, id, YOUSSEF, Kind.BONUS, BigDecimal.ONE,
                "Not ours", STAFF), 404, "RUN_NOT_FOUND");
        assertRefused(() -> service.discard(RIVAL, id, STAFF), 404, "RUN_NOT_FOUND");
    }

    @Test
    @DisplayName("only a draft is discarded, and what was done to it stays in the trail")
    void discard() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        UUID id = service.start(COMPANY, OCT_1, STAFF, TOKEN).run().getId();

        service.discard(COMPANY, id, STAFF);

        assertThat(runRows).doesNotContainKey(id);
        assertThat(slipRows).isEmpty();
        assertThat(lineRows).isEmpty();
        assertThat(eventRows).extracting(CarrierPayrollEvent::getAction)
                .containsExactly(Action.RUN_STARTED, Action.RUN_DISCARDED);
    }

    @Test
    @DisplayName("the period list walks back from today under the rules each period was paid by")
    void periods() {
        rules("2026-09-01", PayCycle.SEMI_MONTHLY, "2.00", null);
        delivered(YOUSSEF, "2026-10-05");
        UUID id = service.start(COMPANY, OCT_1, STAFF, TOKEN).run().getId();

        CarrierPayrollService.PeriodsPage page = service.periods(COMPANY);

        assertThat(page.hasPolicy()).isTrue();
        assertThat(page.periods()).extracting(CarrierPayrollService.PeriodRow::from)
                .containsExactly(OCT_16, OCT_1, LocalDate.parse("2026-09-16"),
                        LocalDate.parse("2026-09-01"));
        CarrierPayrollService.PeriodRow current = page.periods().get(0);
        assertThat(current.over()).isFalse();
        assertThat(current.run()).isNull();
        assertThat(current.payable()).isNull();
        CarrierPayrollService.PeriodRow first = page.periods().get(1);
        assertThat(first.run().getId()).isEqualTo(id);
        assertThat(first.riders()).isEqualTo(1);
        assertThat(first.payable()).isEqualByComparingTo("2.00");
        assertThat(first.over()).isTrue();

        policyRows.clear();
        assertThat(service.periods(COMPANY).hasPolicy()).isFalse();
    }

    @Test
    @DisplayName("payroll never writes the platform's books: no ledger row, no posting, only a custody hand-over")
    void neverPlatformMoney() {
        holds(YOUSSEF, "1.00", "2026-10-05");
        RunView run = approvedFirstHalf();
        service.payAll(COMPANY, run.run().getId(), run.totals().outstanding(), Method.CASH, null,
                STAFF);

        verify(riderLedger, never()).save(any());
        verify(riderLedger, never()).saveAll(any());
        verify(cashFloat, never()).remit(anyString(), any(), any(), any());
        assertThat(Arrays.stream(CarrierPayrollService.class.getDeclaredConstructors())
                .flatMap(c -> Arrays.stream(c.getParameterTypes()))
                .toList())
                .doesNotContain(AccountingTransactionRepository.class, BankPostingPublisher.class,
                        RiderCashOutRepository.class, PointsEntryRepository.class);
    }

    /** A clock a test can move forward, the way the calendar moves under a payroll. */
    static final class MovableClock extends Clock {
        private Instant now;

        MovableClock(Instant now) {
            this.now = now;
        }

        void set(String instant) {
            this.now = Instant.parse(instant);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            MovableClock self = this;
            return new Clock() {
                @Override
                public ZoneId getZone() {
                    return zone;
                }

                @Override
                public Clock withZone(ZoneId other) {
                    return self.withZone(other);
                }

                @Override
                public Instant instant() {
                    return self.instant();
                }
            };
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
