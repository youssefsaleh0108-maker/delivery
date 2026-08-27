package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One duty transition, appended and never modified.
 *
 * <p>{@link RiderPresence} only ever holds the current answer, and "was this rider on duty at
 * 14:00 last Tuesday" is asked by payroll and by anyone investigating a late delivery — weeks
 * later, when the current answer is worthless.
 *
 * <p>Grows per transition, not per ping: a few rows per rider per day, which is why this is a plain
 * table with a dated retention sweep rather than another partitioned one. See
 * {@code TrackingPartitionMaintenance} for the sweep and V12 for why partitioning it would be
 * ceremony.
 */
@Entity
@Table(name = "rider_duty_events")
public class RiderDutyEvent {

    /** Who caused the transition. A rider going off duty and a supervisor doing it are not the same event. */
    public enum Source {
        /** The rider, through their own app. */
        RIDER,
        /** A backoffice operator, e.g. ending an abandoned shift. */
        BACKOFFICE,
        /** The platform itself. Reserved for automatic expiry, which is not written today. */
        SYSTEM
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "rider_id", nullable = false, length = 64)
    private String riderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "duty_state", nullable = false, length = 16)
    private DutyState dutyState;

    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, length = 16)
    private Source source;

    @Column(name = "occurred_at", nullable = false)
    private Instant occurredAt;

    protected RiderDutyEvent() {
        // for JPA
    }

    public RiderDutyEvent(String riderId, DutyState dutyState, Source source, Instant occurredAt) {
        this.id = UUID.randomUUID();
        this.riderId = riderId;
        this.dutyState = dutyState;
        this.source = source;
        this.occurredAt = occurredAt;
    }

    public UUID getId() {
        return id;
    }

    public String getRiderId() {
        return riderId;
    }

    public DutyState getDutyState() {
        return dutyState;
    }

    public Source getSource() {
        return source;
    }

    public Instant getOccurredAt() {
        return occurredAt;
    }
}
