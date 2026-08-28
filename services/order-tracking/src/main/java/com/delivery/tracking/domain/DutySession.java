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
 * One shift: opened when a rider goes on duty, closed when they go off.
 *
 * <p>This is the row "hours online" is summed from. {@link RiderDutyEvent} records the same
 * boundaries as individual facts, but a log of transitions has to be re-paired into intervals on
 * every read and silently produces nonsense the moment one transition is missing; a session states
 * the interval once, at write time, and the aggregate is a plain sum. Both are kept: the event log
 * answers "what happened and who did it", the session answers "how long".
 *
 * <p>A session that was never closed by anyone — the rider's phone died, or they walked away
 * without tapping "go offline" — is closed by the expiry sweep at the rider's last sighting, not at
 * the moment the sweep noticed. See {@link #close} and the migration note on {@code duty_sessions}.
 */
@Entity
@Table(name = "duty_sessions")
public class DutySession {

    /** Who ended the shift. An open session has no reason yet, which the schema also enforces. */
    public enum EndReason {
        /** The rider, through their own app. */
        RIDER,
        /** A backoffice operator ending it on the rider's behalf. */
        BACKOFFICE,
        /** The staleness sweep, for a rider who went silent and never came back. */
        EXPIRED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "rider_id", nullable = false, updatable = false, length = 64)
    private String riderId;

    @Column(name = "started_at", nullable = false, updatable = false)
    private Instant startedAt;

    /** Null while the shift is running. */
    @Column(name = "ended_at")
    private Instant endedAt;

    @Enumerated(EnumType.STRING)
    @Column(name = "end_reason", length = 16)
    private EndReason endReason;

    protected DutySession() {
        // for JPA
    }

    private DutySession(String riderId, Instant startedAt) {
        this.id = UUID.randomUUID();
        this.riderId = riderId;
        this.startedAt = startedAt;
    }

    /** A shift that has just begun. */
    public static DutySession open(String riderId, Instant at) {
        return new DutySession(riderId, at);
    }

    /**
     * Ends the shift.
     *
     * <p>The end is clamped to the start rather than trusted. The expiry sweep closes at the
     * rider's {@code last_seen_at}, and a rider who declared duty and then never pinged has a last
     * sighting from before the shift — or none at all. The honest duration of a shift with no
     * evidence anyone was out there is zero, not negative and not "until we noticed".
     */
    public void close(Instant at, EndReason reason) {
        this.endedAt = at.isBefore(startedAt) ? startedAt : at;
        this.endReason = reason;
    }

    public boolean isOpen() {
        return endedAt == null;
    }

    public UUID getId() {
        return id;
    }

    public String getRiderId() {
        return riderId;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public Instant getEndedAt() {
        return endedAt;
    }

    public EndReason getEndReason() {
        return endReason;
    }
}
