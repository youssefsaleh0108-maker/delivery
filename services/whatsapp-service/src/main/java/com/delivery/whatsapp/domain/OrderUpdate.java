package com.delivery.whatsapp.domain;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * A record that the customer has already been told about one status of one order.
 *
 * <p>The composite key is the whole point. Bus delivery is at-least-once, so the same status event
 * arrives more than once as a matter of course, and a customer told twice that their food is on the
 * way is being told the platform is broken.
 */
@Entity
@Table(name = "wa_order_updates")
@IdClass(OrderUpdate.Key.class)
public class OrderUpdate {

    @Id
    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Id
    @Column(name = "status", nullable = false, updatable = false, length = 24)
    private String status;

    @Column(name = "conversation_id", nullable = false, updatable = false)
    private UUID conversationId;

    @Column(name = "notified_at", nullable = false, insertable = false, updatable = false)
    private Instant notifiedAt;

    protected OrderUpdate() {
        // for JPA
    }

    public OrderUpdate(UUID orderId, String status, UUID conversationId) {
        this.orderId = orderId;
        this.status = status;
        this.conversationId = conversationId;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getStatus() {
        return status;
    }

    public UUID getConversationId() {
        return conversationId;
    }

    public Instant getNotifiedAt() {
        return notifiedAt;
    }

    /** The composite key: one message per order per status. */
    public static class Key implements Serializable {

        private UUID orderId;
        private String status;

        public Key() {
        }

        public Key(UUID orderId, String status) {
            this.orderId = orderId;
            this.status = status;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            return other instanceof Key key
                    && Objects.equals(orderId, key.orderId)
                    && Objects.equals(status, key.status);
        }

        @Override
        public int hashCode() {
            return Objects.hash(orderId, status);
        }
    }
}
