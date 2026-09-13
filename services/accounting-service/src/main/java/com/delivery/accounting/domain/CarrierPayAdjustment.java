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
 * A correction to an approved pay run, paid in the rider's next one.
 *
 * <p>How a mistake in a frozen run is fixed without editing it: the run keeps reading what the rider
 * was shown, this row says what was wrong and by how much, and the next draft for that rider carries
 * it as its own line. It is applied exactly once — when that later run is approved — so two drafts
 * that both show it cannot both pay it.
 */
@Entity
@Table(name = "carrier_pay_adjustment")
public class CarrierPayAdjustment {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "carrier_ref", nullable = false, updatable = false, length = 64)
    private String carrierRef;

    @Column(name = "corrects_run_id", nullable = false, updatable = false)
    private UUID correctsRunId;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 16)
    private CarrierPayLine.Kind kind;

    @Column(name = "amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "reason", nullable = false, updatable = false, length = 500)
    private String reason;

    @Column(name = "created_by", nullable = false, updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "applied_run_id")
    private UUID appliedRunId;

    @Column(name = "applied_at")
    private Instant appliedAt;

    protected CarrierPayAdjustment() {
        // for JPA
    }

    public static CarrierPayAdjustment of(String carrierRef, UUID correctsRunId, String riderRef,
                                          CarrierPayLine.Kind kind, BigDecimal amount,
                                          String reason, String createdBy, Instant at) {
        if (kind != CarrierPayLine.Kind.BONUS && kind != CarrierPayLine.Kind.DEDUCTION) {
            throw new IllegalArgumentException("A correction is a bonus or a deduction");
        }
        if (amount == null || amount.signum() <= 0) {
            throw new IllegalArgumentException("A correction is more than nothing");
        }
        CarrierPayAdjustment adjustment = new CarrierPayAdjustment();
        adjustment.id = UUID.randomUUID();
        adjustment.carrierRef = carrierRef;
        adjustment.correctsRunId = correctsRunId;
        adjustment.riderRef = riderRef;
        adjustment.kind = kind;
        adjustment.amount = amount;
        adjustment.reason = reason;
        adjustment.createdBy = createdBy;
        adjustment.createdAt = at;
        return adjustment;
    }

    /** Paid in {@code runId}, now approved. Once only. */
    public void appliedTo(UUID runId, Instant at) {
        if (appliedRunId != null) {
            throw new IllegalStateException("This correction was already paid in another run");
        }
        if (runId.equals(correctsRunId)) {
            throw new IllegalArgumentException("A correction is paid in a later run, not its own");
        }
        this.appliedRunId = runId;
        this.appliedAt = at;
    }

    public boolean isPending() {
        return appliedRunId == null;
    }

    public UUID getId() {
        return id;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public UUID getCorrectsRunId() {
        return correctsRunId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public CarrierPayLine.Kind getKind() {
        return kind;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getReason() {
        return reason;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public UUID getAppliedRunId() {
        return appliedRunId;
    }

    public Instant getAppliedAt() {
        return appliedAt;
    }
}
