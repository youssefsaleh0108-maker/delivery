package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One line of a payslip: how a figure on it came about.
 *
 * <p>The amount is never negative; {@link Kind#isDeduction()} says which side of the payslip the line
 * is on. Computed lines are regenerated with their draft. A company's named bonus or deduction is
 * taken off a draft by marking it removed, not by deleting it, so who added what stays answerable.
 */
@Entity
@Table(name = "carrier_pay_line")
public class CarrierPayLine {

    public enum Kind {
        /** Deliveries times the per-delivery rate. */
        DELIVERIES(false),
        /** Ordinary hours the rider app recorded, times the hourly rate. */
        HOURS(false),
        /** Recorded hours past the rider's shifts, at the overtime rate. */
        OVERTIME(false),
        /** Hours the office typed. Paid or not by the policy; shown either way. */
        MANUAL_HOURS(false),
        LATE_DEDUCTION(true),
        ABSENCE_DEDUCTION(true),
        /** Cash the rider held for the company, kept out of this pay. */
        CASH_HELD(true),
        /** A named bonus: the company's words. */
        BONUS(false),
        /** A named deduction: the company's words. */
        DEDUCTION(true);

        private final boolean deduction;

        Kind(boolean deduction) {
            this.deduction = deduction;
        }

        public boolean isDeduction() {
            return deduction;
        }

        /** A line a person may add or a correction may carry: BONUS or DEDUCTION, else null. */
        public static Kind parseNamed(String value) {
            if (value == null || value.isBlank()) {
                return null;
            }
            String v = value.trim();
            if (BONUS.name().equalsIgnoreCase(v)) {
                return BONUS;
            }
            if (DEDUCTION.name().equalsIgnoreCase(v)) {
                return DEDUCTION;
            }
            return null;
        }
    }

    public enum Source {
        /** From the policy and the facts. */
        COMPUTED,
        /** A company's named bonus or deduction on a draft. */
        MANUAL,
        /** A correction to an earlier, approved run, paid in this one. */
        ADJUSTMENT
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "run_id", nullable = false, updatable = false)
    private UUID runId;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 24)
    private Kind kind;

    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, updatable = false, length = 16)
    private Source source;

    @Column(name = "label", updatable = false, length = 500)
    private String label;

    @Column(name = "quantity", updatable = false, precision = 14, scale = 4)
    private BigDecimal quantity;

    @Column(name = "rate", updatable = false, precision = 14, scale = 4)
    private BigDecimal rate;

    @Column(name = "amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "adjustment_id", updatable = false)
    private UUID adjustmentId;

    @Column(name = "created_by", updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "removed_by", length = 64)
    private String removedBy;

    @Column(name = "removed_at")
    private Instant removedAt;

    protected CarrierPayLine() {
        // for JPA
    }

    private static CarrierPayLine of(UUID runId, String riderRef, Kind kind, Source source,
                                     BigDecimal amount, Instant at) {
        if (amount == null || amount.signum() < 0) {
            throw new IllegalArgumentException("A pay line's amount is never negative");
        }
        CarrierPayLine line = new CarrierPayLine();
        line.id = UUID.randomUUID();
        line.runId = runId;
        line.riderRef = riderRef;
        line.kind = kind;
        line.source = source;
        line.amount = amount;
        line.createdAt = at;
        return line;
    }

    public static CarrierPayLine computed(UUID runId, String riderRef, Kind kind,
                                          BigDecimal quantity, BigDecimal rate, BigDecimal amount,
                                          Instant at) {
        if (kind == Kind.BONUS || kind == Kind.DEDUCTION) {
            throw new IllegalArgumentException("A named line is added by a person, not computed");
        }
        CarrierPayLine line = of(runId, riderRef, kind, Source.COMPUTED, amount, at);
        line.quantity = quantity;
        line.rate = rate;
        return line;
    }

    /** A company's named bonus or deduction on a draft. */
    public static CarrierPayLine manual(UUID runId, String riderRef, Kind kind, String label,
                                        BigDecimal amount, String by, Instant at) {
        requireNamed(kind, label, amount, by);
        CarrierPayLine line = of(runId, riderRef, kind, Source.MANUAL, amount, at);
        line.label = label;
        line.createdBy = by;
        return line;
    }

    /** A correction to an earlier run, carried into this one. */
    public static CarrierPayLine adjustment(UUID runId, CarrierPayAdjustment adjustment,
                                            Instant at) {
        requireNamed(adjustment.getKind(), adjustment.getReason(), adjustment.getAmount(),
                adjustment.getCreatedBy());
        CarrierPayLine line = of(runId, adjustment.getRiderRef(), adjustment.getKind(),
                Source.ADJUSTMENT, adjustment.getAmount(), at);
        line.label = adjustment.getReason();
        line.adjustmentId = adjustment.getId();
        line.createdBy = adjustment.getCreatedBy();
        return line;
    }

    private static void requireNamed(Kind kind, String label, BigDecimal amount, String by) {
        if ((kind != Kind.BONUS && kind != Kind.DEDUCTION) || label == null || label.isBlank()
                || amount == null || amount.signum() <= 0 || by == null) {
            throw new IllegalArgumentException(
                    "A named line is a bonus or a deduction, with words, an amount and a person");
        }
    }

    /** Takes a company's named line off its draft. The row stays, marked. */
    public void remove(String by, Instant at) {
        if (source != Source.MANUAL) {
            throw new IllegalStateException("Only a line somebody added can be taken off");
        }
        if (removedAt != null) {
            return;
        }
        this.removedBy = by;
        this.removedAt = at;
    }

    public boolean isRemoved() {
        return removedAt != null;
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

    public Kind getKind() {
        return kind;
    }

    public Source getSource() {
        return source;
    }

    public String getLabel() {
        return label;
    }

    public BigDecimal getQuantity() {
        return quantity;
    }

    public BigDecimal getRate() {
        return rate;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public UUID getAdjustmentId() {
        return adjustmentId;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public String getRemovedBy() {
        return removedBy;
    }

    public Instant getRemovedAt() {
        return removedAt;
    }
}
