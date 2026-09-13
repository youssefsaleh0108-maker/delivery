package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One rider's pay in one run.
 *
 * <p>The figures are written once and never updated — every money column is insert-only — so an
 * approved payslip cannot be changed by any code path, only replaced while its run is still a draft.
 * What moves afterwards is the payment status: DUE, then PAID (or FAILED and then PAID), recorded by
 * the company, which pays its riders itself. Nothing here moves money.
 *
 * <p>The arithmetic is also a database rule ({@code chk_payslip_gross}, {@code chk_payslip_net}), so
 * a payslip whose parts do not make its total cannot be stored however it was computed.
 */
@Entity
@Table(name = "carrier_payslip")
public class CarrierPayslip {

    public enum Status {
        /** On a draft run. */
        DRAFT,
        /** Approved with pay to hand over, and no payment recorded yet. */
        DUE,
        /** Approved with nothing to pay: deductions took all of it, or more. */
        NOTHING_DUE,
        /** The company recorded paying it. Final. */
        PAID,
        /** The company recorded a payment that did not go through. Still owed. */
        FAILED
    }

    /**
     * Everything a payslip says, as computed.
     *
     * <p>{@link #sameAs} compares amounts by value, because 2.5 and 2.50 are the same pay and a
     * figure read back from the database carries its column's scale.
     *
     * @param workedSeconds   duty time the rider app recorded; null when no attendance was read for
     *                        this rider — unknown, not zero
     * @param manualSeconds   hours the office typed for days with no recorded time
     * @param overtimeSeconds the part of {@code workedSeconds} past the rider's shifts
     * @param basePay         paid for hours: ordinary, overtime and, when the policy pays them, typed
     * @param deliveryPay     paid per delivery
     * @param bonuses         named bonuses and bonus corrections
     * @param deductions      lateness, absence, named deductions, deduction corrections and netted
     *                        cash
     * @param tips            informational only: the rider's own money, never in gross or net
     * @param cashHeld        what the rider held for the company when computed
     * @param cashNetted      the part of it kept out of this pay: all of it, or nothing
     */
    public record Figures(int deliveries, Long workedSeconds, Long manualSeconds,
                          Long overtimeSeconds, Integer lates, Integer absences,
                          BigDecimal basePay, BigDecimal deliveryPay, BigDecimal bonuses,
                          BigDecimal deductions, BigDecimal gross, BigDecimal net,
                          BigDecimal tips, BigDecimal cashHeld, BigDecimal cashNetted) {

        public boolean sameAs(Figures other) {
            return other != null
                    && deliveries == other.deliveries
                    && Objects.equals(workedSeconds, other.workedSeconds)
                    && Objects.equals(manualSeconds, other.manualSeconds)
                    && Objects.equals(overtimeSeconds, other.overtimeSeconds)
                    && Objects.equals(lates, other.lates)
                    && Objects.equals(absences, other.absences)
                    && same(basePay, other.basePay)
                    && same(deliveryPay, other.deliveryPay)
                    && same(bonuses, other.bonuses)
                    && same(deductions, other.deductions)
                    && same(gross, other.gross)
                    && same(net, other.net)
                    && same(tips, other.tips)
                    && same(cashHeld, other.cashHeld)
                    && same(cashNetted, other.cashNetted);
        }

        private static boolean same(BigDecimal a, BigDecimal b) {
            return a == null ? b == null : b != null && a.compareTo(b) == 0;
        }
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "run_id", nullable = false, updatable = false)
    private UUID runId;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Column(name = "deliveries", nullable = false, updatable = false)
    private int deliveries;

    @Column(name = "worked_seconds", updatable = false)
    private Long workedSeconds;

    @Column(name = "manual_seconds", updatable = false)
    private Long manualSeconds;

    @Column(name = "overtime_seconds", updatable = false)
    private Long overtimeSeconds;

    @Column(name = "lates", updatable = false)
    private Integer lates;

    @Column(name = "absences", updatable = false)
    private Integer absences;

    @Column(name = "base_pay", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal basePay;

    @Column(name = "delivery_pay", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal deliveryPay;

    @Column(name = "bonuses", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal bonuses;

    @Column(name = "deductions", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal deductions;

    @Column(name = "gross", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal gross;

    @Column(name = "net", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal net;

    @Column(name = "tips", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal tips;

    @Column(name = "cash_held", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal cashHeld;

    @Column(name = "cash_netted", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal cashNetted;

    /** Set once, at approval, when cash was netted. */
    @Column(name = "handover_id")
    private UUID handoverId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    @Enumerated(EnumType.STRING)
    @Column(name = "paid_method", length = 24)
    private CashFloatEntry.Method paidMethod;

    @Column(name = "paid_reference", length = 120)
    private String paidReference;

    @Column(name = "paid_by", length = 64)
    private String paidBy;

    @Column(name = "paid_at")
    private Instant paidAt;

    @Column(name = "failure_reason", length = 500)
    private String failureReason;

    @Column(name = "failed_by", length = 64)
    private String failedBy;

    @Column(name = "failed_at")
    private Instant failedAt;

    protected CarrierPayslip() {
        // for JPA
    }

    public static CarrierPayslip draft(UUID runId, String riderRef, Figures f) {
        CarrierPayslip slip = new CarrierPayslip();
        slip.id = UUID.randomUUID();
        slip.runId = runId;
        slip.riderRef = riderRef;
        slip.deliveries = f.deliveries();
        slip.workedSeconds = f.workedSeconds();
        slip.manualSeconds = f.manualSeconds();
        slip.overtimeSeconds = f.overtimeSeconds();
        slip.lates = f.lates();
        slip.absences = f.absences();
        slip.basePay = f.basePay();
        slip.deliveryPay = f.deliveryPay();
        slip.bonuses = f.bonuses();
        slip.deductions = f.deductions();
        slip.gross = f.gross();
        slip.net = f.net();
        slip.tips = f.tips();
        slip.cashHeld = f.cashHeld();
        slip.cashNetted = f.cashNetted();
        slip.status = Status.DRAFT;
        return slip;
    }

    public Figures figures() {
        return new Figures(deliveries, workedSeconds, manualSeconds, overtimeSeconds, lates,
                absences, basePay, deliveryPay, bonuses, deductions, gross, net, tips, cashHeld,
                cashNetted);
    }

    /**
     * Frozen with its run.
     *
     * @param handoverId the hand-over that netted this rider's cash; required exactly when cash was
     *                   netted, so an approved payslip can never claim a deduction the float does
     *                   not show
     */
    public void approve(UUID handoverId) {
        if (status != Status.DRAFT) {
            throw new IllegalStateException("This payslip is already approved");
        }
        if ((cashNetted.signum() > 0) != (handoverId != null)) {
            throw new IllegalStateException(
                    "Netted cash must name the hand-over that took it, and only netted cash may");
        }
        this.handoverId = handoverId;
        this.status = net.signum() > 0 ? Status.DUE : Status.NOTHING_DUE;
    }

    /** The company recorded paying this rider. */
    public void markPaid(CashFloatEntry.Method method, String reference, String by, Instant at) {
        if (!isOutstanding()) {
            throw new IllegalStateException("Only a payslip still owed can be marked paid");
        }
        if (method == null || method == CashFloatEntry.Method.PAYROLL_DEDUCTION) {
            throw new IllegalArgumentException("Say how the rider was paid");
        }
        this.status = Status.PAID;
        this.paidMethod = method;
        this.paidReference = reference;
        this.paidBy = by;
        this.paidAt = at;
    }

    /** The company recorded a payment that did not go through. The pay is still owed. */
    public void markFailed(String reason, String by, Instant at) {
        if (!isOutstanding()) {
            throw new IllegalStateException("Only a payslip still owed can fail");
        }
        this.status = Status.FAILED;
        this.failureReason = reason;
        this.failedBy = by;
        this.failedAt = at;
    }

    /** Owed and not yet recorded as paid. */
    public boolean isOutstanding() {
        return status == Status.DUE || status == Status.FAILED;
    }

    /** Whether a rider in this state has cash of the company's netted against this pay. */
    public boolean nettedCash() {
        return cashNetted.signum() > 0;
    }

    public UUID getId() {
        return id;
    }

    public UUID getRunId() {
        return runId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public BigDecimal getNet() {
        return net;
    }

    public BigDecimal getBonuses() {
        return bonuses;
    }

    public BigDecimal getCashNetted() {
        return cashNetted;
    }

    public UUID getHandoverId() {
        return handoverId;
    }

    public Status getStatus() {
        return status;
    }

    public CashFloatEntry.Method getPaidMethod() {
        return paidMethod;
    }

    public String getPaidReference() {
        return paidReference;
    }

    public String getPaidBy() {
        return paidBy;
    }

    public Instant getPaidAt() {
        return paidAt;
    }

    public String getFailureReason() {
        return failureReason;
    }

    public String getFailedBy() {
        return failedBy;
    }

    public Instant getFailedAt() {
        return failedAt;
    }
}
