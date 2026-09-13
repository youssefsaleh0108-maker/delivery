package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One version of a delivery company's pay rules for the riders it employs.
 *
 * <p><strong>The company's rules, not the platform's.</strong> What a company pays its riders is its
 * own employment contract ({@link RiderLedgerEntry.PayableBy#CARRIER}), and the owner has decided
 * none of these numbers — so every one of them is a field the company sets, and the defaults below
 * are the answer to "what happens before it says anything", not a policy the platform imposes.
 *
 * <p><strong>Immutable, and versioned by the period it starts.</strong> Saving rules writes a new row;
 * nothing is ever edited. A version takes effect on the first day of a pay period, so a period is
 * always paid under exactly one set of rules, a draft recomputed tomorrow gives today's answer, and
 * an approved run names the version it used for good.
 */
@Entity
@Table(name = "carrier_pay_policy")
public class CarrierPayPolicy {

    /** How a company's calendar is cut into pay periods. */
    public enum PayCycle {
        /** The 1st to the 15th, and the 16th to the month's end — the design's "bi-weekly" periods. */
        SEMI_MONTHLY,
        /** The whole calendar month. */
        MONTHLY;

        /** Case-insensitive; null for anything that is not one. */
        public static PayCycle parse(String value) {
            if (value == null || value.isBlank()) {
                return null;
            }
            for (PayCycle cycle : values()) {
                if (cycle.name().equalsIgnoreCase(value.trim())) {
                    return cycle;
                }
            }
            return null;
        }
    }

    /**
     * The rules a payslip is computed with.
     *
     * @param perDeliveryRate    paid per delivered job for the company
     * @param hourlyRate         paid per hour of duty time the rider app recorded; null for no hourly
     *                           base at all
     * @param payManualHours     whether hours the office typed into the attendance log, for days the
     *                           app recorded nothing, are paid too. Shown apart from recorded hours
     *                           either way
     * @param overtimeMultiplier what an overtime hour is worth against an ordinary one
     * @param lateDeduction      taken per unexcused late day
     * @param absenceDeduction   taken per unexcused absence
     */
    public record Terms(PayCycle cycle, BigDecimal perDeliveryRate, BigDecimal hourlyRate,
                        boolean payManualHours, BigDecimal overtimeMultiplier,
                        BigDecimal lateDeduction, BigDecimal absenceDeduction) {

        /**
         * Whether a pay run under these rules has to read attendance at all. A company paying by the
         * delivery with no lateness rules never depends on order-tracking being up.
         */
        public boolean needsAttendance() {
            return hourlyRate != null || lateDeduction.signum() > 0 || absenceDeduction.signum() > 0;
        }
    }

    /** The semi-monthly calendar the design draws. */
    public static final PayCycle DEFAULT_CYCLE = PayCycle.SEMI_MONTHLY;
    /** Office-typed hours are paid, and shown separately from recorded ones. */
    public static final boolean DEFAULT_PAY_MANUAL_HOURS = true;
    /** An overtime hour is paid as an ordinary hour until the company says otherwise. */
    public static final BigDecimal DEFAULT_OVERTIME_MULTIPLIER = new BigDecimal("1.00");
    /** No deduction for lateness or absence until the company sets one. */
    public static final BigDecimal DEFAULT_LATE_DEDUCTION = new BigDecimal("0.00");
    public static final BigDecimal DEFAULT_ABSENCE_DEDUCTION = new BigDecimal("0.00");

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "carrier_ref", nullable = false, updatable = false, length = 64)
    private String carrierRef;

    @Column(name = "effective_from", nullable = false, updatable = false)
    private LocalDate effectiveFrom;

    @Enumerated(EnumType.STRING)
    @Column(name = "pay_cycle", nullable = false, updatable = false, length = 16)
    private PayCycle payCycle;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    @Column(name = "per_delivery_rate", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal perDeliveryRate;

    @Column(name = "hourly_rate", updatable = false, precision = 12, scale = 2)
    private BigDecimal hourlyRate;

    @Column(name = "pay_manual_hours", nullable = false, updatable = false)
    private boolean payManualHours;

    @Column(name = "overtime_multiplier", nullable = false, updatable = false, precision = 4, scale = 2)
    private BigDecimal overtimeMultiplier;

    @Column(name = "late_deduction", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal lateDeduction;

    @Column(name = "absence_deduction", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal absenceDeduction;

    @Column(name = "created_by", nullable = false, updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected CarrierPayPolicy() {
        // for JPA
    }

    /** A new version of a company's rules, starting on {@code effectiveFrom}. */
    public static CarrierPayPolicy version(String carrierRef, LocalDate effectiveFrom, Terms terms,
                                           String currency, String createdBy, Instant createdAt) {
        CarrierPayPolicy policy = new CarrierPayPolicy();
        policy.id = UUID.randomUUID();
        policy.carrierRef = carrierRef;
        policy.effectiveFrom = effectiveFrom;
        policy.payCycle = terms.cycle();
        policy.currency = currency;
        policy.perDeliveryRate = terms.perDeliveryRate();
        policy.hourlyRate = terms.hourlyRate();
        policy.payManualHours = terms.payManualHours();
        policy.overtimeMultiplier = terms.overtimeMultiplier();
        policy.lateDeduction = terms.lateDeduction();
        policy.absenceDeduction = terms.absenceDeduction();
        policy.createdBy = createdBy;
        policy.createdAt = createdAt;
        return policy;
    }

    public Terms terms() {
        return new Terms(payCycle, perDeliveryRate, hourlyRate, payManualHours, overtimeMultiplier,
                lateDeduction, absenceDeduction);
    }

    public UUID getId() {
        return id;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public LocalDate getEffectiveFrom() {
        return effectiveFrom;
    }

    public PayCycle getPayCycle() {
        return payCycle;
    }

    public String getCurrency() {
        return currency;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
