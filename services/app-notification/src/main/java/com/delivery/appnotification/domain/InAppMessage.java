package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * One message in a user's in-app inbox.
 *
 * <p>Distinct from the manager's notification_log row it came from: that row records what the
 * platform tried to send, this one is the user's copy and carries read state. Keeping them apart
 * means marking a message read cannot alter the delivery record.
 */
@Entity
@Table(name = "in_app_messages")
public class InAppMessage {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "user_id", nullable = false, length = 64)
    private String userId;

    /** The notification_log id. Unique, so a redelivered command cannot create a second copy. */
    @Column(name = "notification_id", nullable = false, updatable = false)
    private UUID notificationId;

    @Column(name = "order_id")
    private UUID orderId;

    @Column(name = "event_type", nullable = false, length = 64)
    private String eventType;

    @Column(name = "title", nullable = false, length = 255)
    private String title;

    @Column(name = "body", nullable = false, columnDefinition = "text")
    private String body;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "metadata", nullable = false, columnDefinition = "jsonb")
    private Map<String, String> metadata = new LinkedHashMap<>();

    @Column(name = "read_at")
    private Instant readAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected InAppMessage() {
        // for JPA
    }

    public InAppMessage(String userId, UUID notificationId, UUID orderId, String eventType,
                        String title, String body, Map<String, String> metadata) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.notificationId = notificationId;
        this.orderId = orderId;
        this.eventType = eventType;
        this.title = title;
        this.body = body;
        this.metadata = metadata == null ? new LinkedHashMap<>() : new LinkedHashMap<>(metadata);
        this.createdAt = Instant.now();
    }

    /**
     * Idempotent: re-marking an already-read message keeps the original timestamp.
     *
     * <p>A client that fires "mark read" on every render would otherwise keep pushing the time
     * forward, and "when did they actually see this" would stop being answerable.
     */
    public void markRead() {
        if (readAt == null) {
            readAt = Instant.now();
        }
    }

    public UUID getId() {
        return id;
    }

    public String getUserId() {
        return userId;
    }

    public UUID getNotificationId() {
        return notificationId;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getEventType() {
        return eventType;
    }

    public String getTitle() {
        return title;
    }

    public String getBody() {
        return body;
    }

    public Map<String, String> getMetadata() {
        return Map.copyOf(metadata);
    }

    public Instant getReadAt() {
        return readAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
