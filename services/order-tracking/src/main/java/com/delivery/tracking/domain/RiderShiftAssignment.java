package com.delivery.tracking.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * That a rider works a shift from one date to another — one row of a schedule's history.
 *
 * <p>A history rather than a pointer on the rider, because a past day must be judged against the
 * shift that applied on that day. Moving a rider closes this row the day before the new one starts
 * ({@link #endOn}); it is never rewritten to say something it did not say at the time.
 */
@Entity
@Table(name = "rider_shift_assignments")
public class RiderShiftAssignment {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "rider_id", nullable = false, updatable = false, length = 64)
    private String riderId;

    @Column(name = "carrier_id", nullable = false, updatable = false)
    private UUID carrierId;

    @Column(name = "template_id", nullable = false, updatable = false)
    private UUID templateId;

    @Column(name = "effective_from", nullable = false, updatable = false)
    private LocalDate effectiveFrom;

    /** Inclusive; null while open-ended. */
    @Column(name = "effective_to")
    private LocalDate effectiveTo;

    @Column(name = "created_by", nullable = false, updatable = false, length = 64)
    private String createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected RiderShiftAssignment() {
        // for JPA
    }

    public static RiderShiftAssignment start(String riderId, UUID carrierId, UUID templateId,
                                             LocalDate from, String createdBy, Instant now) {
        RiderShiftAssignment a = new RiderShiftAssignment();
        a.id = UUID.randomUUID();
        a.riderId = riderId;
        a.carrierId = carrierId;
        a.templateId = templateId;
        a.effectiveFrom = from;
        a.createdBy = createdBy;
        a.createdAt = now;
        return a;
    }

    /** The last day this assignment applies, inclusive. */
    public void endOn(LocalDate lastDay) {
        this.effectiveTo = lastDay;
    }

    public boolean covers(LocalDate day) {
        return !day.isBefore(effectiveFrom) && (effectiveTo == null || !day.isAfter(effectiveTo));
    }

    public UUID getId() {
        return id;
    }

    public String getRiderId() {
        return riderId;
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    public UUID getTemplateId() {
        return templateId;
    }

    public LocalDate getEffectiveFrom() {
        return effectiveFrom;
    }

    public LocalDate getEffectiveTo() {
        return effectiveTo;
    }
}
