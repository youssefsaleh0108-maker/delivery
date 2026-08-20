package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One notification the platform decided to send.
 *
 * <p>Written BEFORE dispatch, deliberately. A log written only on success would be silent about
 * exactly the cases worth investigating — this row is what makes "why didn't this SMS arrive"
 * answerable (Section 10), and its id is the idempotency key the connector uses so a redelivered
 * command cannot send twice.
 */
@Entity
@Table(name = "notification_log")
public class NotificationLog {

    public enum Status { PENDING, SENT, FAILED, DEAD_LETTERED }

    /**
     * What the carrier reported, as opposed to what the provider accepted.
     *
     * <p>Orthogonal to {@link Status} on purpose: a message can be {@code SENT} — accepted and
     * billed — and later come back {@code UNDELIVERED}. Null means no receipt has arrived, which is
     * the normal case for most traffic and is not the same as "not delivered".
     */
    public enum DeliveryStatus { DELIVERED, UNDELIVERED }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "order_id")
    private UUID orderId;

    /** Keycloak sub of whoever this is for. */
    @Column(name = "recipient_id", nullable = false, length = 64)
    private String recipientId;

    @Column(name = "channel", nullable = false, length = 16)
    private String channel;

    /** Phone number, email address, device token or user id, depending on channel. */
    @Column(name = "recipient", nullable = false, length = 255)
    private String recipient;

    @Column(name = "event_type", nullable = false, length = 64)
    private String eventType;

    @Column(name = "subject", columnDefinition = "text")
    private String subject;

    @Column(name = "body", nullable = false, columnDefinition = "text")
    private String body;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "provider", length = 64)
    private String provider;

    @Column(name = "provider_message_id", length = 255)
    private String providerMessageId;

    @Column(name = "failure_reason", columnDefinition = "text")
    private String failureReason;

    @Column(name = "attempts", nullable = false)
    private int attempts;

    @Column(name = "correlation_id", length = 64)
    private String correlationId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "sent_at")
    private Instant sentAt;

    @Enumerated(EnumType.STRING)
    @Column(name = "delivery_status", length = 16)
    private DeliveryStatus deliveryStatus;

    @Column(name = "delivered_at")
    private Instant deliveredAt;

    /** The vendor's own wording, kept verbatim — our two-value enum throws away the detail. */
    @Column(name = "delivery_detail", columnDefinition = "text")
    private String deliveryDetail;

    @Column(name = "dlr_received_at")
    private Instant dlrReceivedAt;

    protected NotificationLog() {
        // for JPA
    }

    public NotificationLog(UUID orderId, String recipientId, String channel, String recipient,
                           String eventType, String subject, String body, String correlationId) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.recipientId = recipientId;
        this.channel = channel;
        this.recipient = recipient;
        this.eventType = eventType;
        this.subject = subject;
        this.body = body;
        this.correlationId = correlationId;
        this.status = Status.PENDING;
        this.createdAt = Instant.now();
    }

    public void markSent(String provider, String providerMessageId) {
        this.status = Status.SENT;
        this.provider = provider;
        this.providerMessageId = providerMessageId;
        this.sentAt = Instant.now();
        this.failureReason = null;
    }

    public void markFailed(String provider, String reason, boolean terminal) {
        this.attempts++;
        this.provider = provider;
        this.failureReason = reason;
        this.status = terminal ? Status.DEAD_LETTERED : Status.FAILED;
    }

    /**
     * Records what the carrier said became of this message.
     *
     * <p><strong>First terminal receipt wins.</strong> The bus is at-least-once and gives no
     * ordering guarantee, so "last write wins" would make the stored outcome depend on the order
     * two redeliveries happened to arrive in — the same message could read DELIVERED or UNDELIVERED
     * depending on the day. Ignoring later receipts makes the result deterministic. A genuine
     * disagreement is worth an operator's attention rather than a silent overwrite, so the caller is
     * told whether anything changed.
     *
     * @return true if this receipt was applied, false if a terminal outcome was already recorded
     */
    public boolean applyDeliveryReceipt(DeliveryStatus reported, String detail, Instant occurredAt) {
        if (reported == null || this.deliveryStatus != null) {
            return false;
        }
        this.deliveryStatus = reported;
        this.deliveryDetail = detail;
        this.dlrReceivedAt = Instant.now();
        // The carrier's timestamp, not ours: the gap between them is queue lag, and conflating the
        // two would make every delivery look instant.
        this.deliveredAt = reported == DeliveryStatus.DELIVERED
                ? (occurredAt != null ? occurredAt : Instant.now())
                : null;
        return true;
    }

    public UUID getId() {
        return id;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getRecipientId() {
        return recipientId;
    }

    public String getChannel() {
        return channel;
    }

    public String getRecipient() {
        return recipient;
    }

    public String getEventType() {
        return eventType;
    }

    public String getSubject() {
        return subject;
    }

    public String getBody() {
        return body;
    }

    public Status getStatus() {
        return status;
    }

    public String getProvider() {
        return provider;
    }

    public String getFailureReason() {
        return failureReason;
    }

    public int getAttempts() {
        return attempts;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getSentAt() {
        return sentAt;
    }

    public String getProviderMessageId() {
        return providerMessageId;
    }

    /** Null when no receipt has arrived — not the same as undelivered. */
    public DeliveryStatus getDeliveryStatus() {
        return deliveryStatus;
    }

    public Instant getDeliveredAt() {
        return deliveredAt;
    }

    public String getDeliveryDetail() {
        return deliveryDetail;
    }

    public Instant getDlrReceivedAt() {
        return dlrReceivedAt;
    }
}
