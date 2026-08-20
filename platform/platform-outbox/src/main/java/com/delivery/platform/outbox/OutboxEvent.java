package com.delivery.platform.outbox;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

/**
 * One pending outbound event, written in the same transaction as the state change that produced it.
 *
 * <p>The table lives in the owning service's own schema — there is no shared outbox. That keeps the
 * "same transaction" guarantee real: a service's business write and its outbox insert are one local
 * commit, with no distributed transaction anywhere.
 */
@Entity
@Table(name = "outbox_event", indexes = {
        @Index(name = "idx_outbox_unpublished", columnList = "status, created_at"),
        @Index(name = "idx_outbox_aggregate", columnList = "aggregate_type, aggregate_id")
})
public class OutboxEvent {

    public enum Status {
        /** Written, not yet on the bus. */
        PENDING,
        /** Confirmed onto the bus by the relay. */
        PUBLISHED,
        /** Retries exhausted; needs an operator. Never silently dropped (Section 10). */
        DEAD_LETTERED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** e.g. {@code Order}, {@code Product} — the entity kind this event is about. */
    @Column(name = "aggregate_type", nullable = false, length = 128)
    private String aggregateType;

    /** The id of that entity, as a string so a service can use UUID or bigint freely. */
    @Column(name = "aggregate_id", nullable = false, length = 128)
    private String aggregateId;

    /** e.g. {@code order.placed}. Doubles as the routing key onto the bus. */
    @Column(name = "event_type", nullable = false, length = 191)
    private String eventType;

    @Column(name = "payload", nullable = false, columnDefinition = "text")
    private String payload;

    /**
     * The correlation id in force when the event was recorded, carried onto the bus so a single
     * customer action stays traceable across every service it fans out to (Section 10).
     */
    @Column(name = "correlation_id", length = 64)
    private String correlationId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private Status status = Status.PENDING;

    @Column(name = "attempts", nullable = false)
    private int attempts;

    @Column(name = "last_error", columnDefinition = "text")
    private String lastError;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "published_at")
    private Instant publishedAt;

    /**
     * When this event becomes eligible for another publish attempt.
     *
     * <p>Equal to {@code createdAt} for a new row, so nothing is ever delayed on its first attempt;
     * only a failure pushes it forward. See {@link #markFailed} for why this exists at all.
     */
    @Column(name = "next_attempt_at", nullable = false)
    private Instant nextAttemptAt;

    protected OutboxEvent() {
        // for JPA
    }

    public OutboxEvent(String aggregateType, String aggregateId, String eventType,
                       String payload, String correlationId) {
        this.id = UUID.randomUUID();
        this.aggregateType = aggregateType;
        this.aggregateId = aggregateId;
        this.eventType = eventType;
        this.payload = payload;
        this.correlationId = correlationId;
        this.status = Status.PENDING;
        this.createdAt = Instant.now();
        this.nextAttemptAt = this.createdAt;
    }

    public void markPublished() {
        this.status = Status.PUBLISHED;
        this.publishedAt = Instant.now();
        this.lastError = null;
    }

    /**
     * Records a failed publish and schedules the retry.
     *
     * <p>The delay doubles per attempt, capped, because the failure this is actually protecting
     * against is the broker being down rather than the message being bad. Retrying on every tick
     * meant a service with a 2s poll and 5 attempts exhausted a row eleven seconds after the broker
     * went away — shorter than a broker restart — and dead-lettered the whole backlog for an outage
     * it should simply have waited out. Backing off turns the same outage into a delay.
     *
     * <p>A genuinely poison message still reaches {@code DEAD_LETTERED}; it just takes the full
     * backoff schedule to get there instead of ten seconds.
     */
    public void markFailed(String error, int maxAttempts, Duration baseBackoff, Duration maxBackoff) {
        this.attempts++;
        this.lastError = error;
        if (this.attempts >= maxAttempts) {
            this.status = Status.DEAD_LETTERED;
            return;
        }
        this.nextAttemptAt = Instant.now().plus(backoffFor(this.attempts, baseBackoff, maxBackoff));
    }

    /**
     * Exponential backoff for the nth attempt: {@code base * 2^(n-1)}, capped at {@code max}.
     *
     * <p>Computed in {@code long} nanos with an explicit shift guard — {@code Duration.multipliedBy}
     * overflows silently into a negative duration past ~63 doublings, which would schedule the retry
     * in the past and reinstate the every-tick hammering this exists to prevent.
     */
    static Duration backoffFor(int attempt, Duration base, Duration max) {
        if (attempt >= 32) {
            return max;
        }
        Duration scaled = base.multipliedBy(1L << (attempt - 1));
        return scaled.compareTo(max) > 0 ? max : scaled;
    }

    public UUID getId() {
        return id;
    }

    public String getAggregateType() {
        return aggregateType;
    }

    public String getAggregateId() {
        return aggregateId;
    }

    public String getEventType() {
        return eventType;
    }

    public String getPayload() {
        return payload;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Status getStatus() {
        return status;
    }

    public int getAttempts() {
        return attempts;
    }

    public String getLastError() {
        return lastError;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getPublishedAt() {
        return publishedAt;
    }

    public Instant getNextAttemptAt() {
        return nextAttemptAt;
    }
}
