package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import com.delivery.notifications.link.NotificationLink;
import com.delivery.notifications.link.NotificationLinkTarget;

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

    /**
     * Where the notification told the app to go, stored as the typed pair rather than the rendered
     * string.
     *
     * <p>Kept on the row because the link is part of what the customer received: "it opened the
     * wrong screen" cannot be answered by recomputing the link from today's rules. Stored as target
     * and id rather than as {@code delivery://orders/…} so the record survives a change to how the
     * string is composed — the scheme is a rendering decision, the destination is the fact.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "link_target", length = 32)
    private NotificationLinkTarget linkTarget;

    @Column(name = "link_id", length = 128)
    private String linkId;

    /**
     * What makes this notification the same notification on a redelivery, when the order is not
     * enough to say so.
     *
     * <p>Null for order events, and that is the common case: an {@code order.status_changed} is
     * unique per (order, type, channel, recipient), so the order id already answers "have we sent
     * this". A chat notification is not — one order carries many messages, and deduplicating on the
     * order would send the customer a push for the rider's first message and silence for every one
     * after it. So the caller that knows what "the same" means supplies a key; here that is the
     * chat message id.
     *
     * <p>Deliberately a free-form string rather than a second uuid column. The next caller with the
     * same problem will have some other kind of id, and a column typed to today's example would
     * push the one after that into inventing a uuid to fit.
     */
    @Column(name = "dedupe_key", length = 128)
    private String dedupeKey;

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

    /**
     * Records where this notification points.
     *
     * <p>A setter rather than a constructor parameter because the link is optional and derived: a
     * fifth positional argument that is null for most callers is the kind of signature people get
     * wrong. Null clears it, which is what a caller with nothing to point at should pass.
     */
    public void pointAt(NotificationLink link) {
        this.linkTarget = link == null ? null : link.target();
        this.linkId = link == null ? null : link.id();
    }

    /** Empty when this notification has no screen to open — most email and SMS. */
    public Optional<NotificationLink> link() {
        return linkTarget == null
                ? Optional.empty()
                : NotificationLink.of(linkTarget, linkId);
    }

    /**
     * Records what makes this notification unique, for callers the order id cannot speak for.
     *
     * <p>A setter for the same reason {@link #pointAt} is one: it is null on every order-event path
     * and only the two or three callers that need it should have to think about it.
     */
    public void dedupeOn(String key) {
        this.dedupeKey = key;
    }

    public String getDedupeKey() {
        return dedupeKey;
    }

    public NotificationLinkTarget getLinkTarget() {
        return linkTarget;
    }

    public String getLinkId() {
        return linkId;
    }
}
