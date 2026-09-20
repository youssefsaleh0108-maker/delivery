package com.delivery.accounting.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A settlement this service could not make and will not retry (RECON-04, V55).
 *
 * <p>Only the messages that will never settle on their own: one that cannot be parsed, one that
 * names no parties or no total, one whose money was never collected. They are acknowledged — a bad
 * message that comes back for ever blocks every good one behind it — and recorded here first, so
 * the Back Office sees an order that needs a person instead of nothing at all.
 *
 * <p>A transient failure is NOT here: it is rethrown, so the listener's retries and the broker's
 * dead-letter queue get it, and the unsettled-deliveries check finds the order again afterwards.
 */
@Entity
@Table(name = "settlement_failure")
public class SettlementFailure {

    /** How much of the message is kept. Longer than any order event this service receives. */
    public static final int MAX_PAYLOAD = 8_000;

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** The order, or null when the message did not name one this service could read. */
    @Column(name = "order_id", updatable = false)
    private UUID orderId;

    @Column(name = "event_type", nullable = false, updatable = false, length = 64)
    private String eventType;

    @Column(name = "reason", nullable = false, columnDefinition = "text")
    private String reason;

    @Column(name = "payload", updatable = false, columnDefinition = "text")
    private String payload;

    @Column(name = "correlation_id", updatable = false, length = 64)
    private String correlationId;

    @Column(name = "first_seen_at", nullable = false, insertable = false, updatable = false)
    private Instant firstSeenAt;

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;

    /** How many times this same message has arrived and been refused. */
    @Column(name = "attempts", nullable = false)
    private int attempts;

    @Column(name = "resolved_at")
    private Instant resolvedAt;

    @Column(name = "resolved_by", length = 64)
    private String resolvedBy;

    @Column(name = "resolution", columnDefinition = "text")
    private String resolution;

    protected SettlementFailure() {
        // for JPA
    }

    public SettlementFailure(UUID orderId, String eventType, String reason, String payload,
                             String correlationId) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.eventType = eventType;
        this.reason = reason;
        this.payload = payload == null || payload.length() <= MAX_PAYLOAD
                ? payload
                : payload.substring(0, MAX_PAYLOAD);
        this.correlationId = correlationId;
        this.lastSeenAt = Instant.now();
        this.attempts = 1;
    }

    /** The same message again: one line, with a count, rather than a row per redelivery. */
    public void seenAgain(String reason) {
        this.reason = reason;
        this.lastSeenAt = Instant.now();
        this.attempts++;
    }

    /**
     * Marks this as dealt with.
     *
     * @param resolution what happened — settled by hand, or judged not owed. Kept because "it went
     *                   away" is the answer nobody can check later
     */
    public void resolve(String by, String resolution) {
        this.resolvedAt = Instant.now();
        this.resolvedBy = by;
        this.resolution = resolution;
    }

    public boolean isOpen() {
        return resolvedAt == null;
    }

    public UUID getId() {
        return id;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getEventType() {
        return eventType;
    }

    public String getReason() {
        return reason;
    }

    public String getPayload() {
        return payload;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Instant getFirstSeenAt() {
        return firstSeenAt;
    }

    public Instant getLastSeenAt() {
        return lastSeenAt;
    }

    public int getAttempts() {
        return attempts;
    }

    public Instant getResolvedAt() {
        return resolvedAt;
    }

    public String getResolvedBy() {
        return resolvedBy;
    }

    public String getResolution() {
        return resolution;
    }
}
