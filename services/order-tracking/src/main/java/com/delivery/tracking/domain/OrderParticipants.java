package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A read-model of who is involved in an order, built entirely from {@code order.*} events.
 *
 * <p>Order Tracking never queries Order Manager. This projection is what makes the authorisation
 * check on the live-tracking read path a local row lookup instead of a cross-service HTTP call on
 * every poll (Section 10).
 *
 * <p>It is eventually consistent, and that is acceptable here: the worst case is a customer seeing
 * "not available yet" for the second or two before the event lands.
 */
@Entity
@Table(name = "order_participants")
public class OrderParticipants {

    @Id
    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Column(name = "customer_id", nullable = false, length = 64)
    private String customerId;

    @Column(name = "merchant_id", nullable = false, length = 64)
    private String merchantId;

    @Column(name = "rider_id", length = 64)
    private String riderId;

    @Column(name = "status", nullable = false, length = 24)
    private String status;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected OrderParticipants() {
        // for JPA
    }

    public OrderParticipants(UUID orderId, String customerId, String merchantId,
                             String riderId, String status) {
        this.orderId = orderId;
        this.customerId = customerId;
        this.merchantId = merchantId;
        this.riderId = riderId;
        this.status = status;
        this.updatedAt = Instant.now();
    }

    public void apply(String riderId, String status) {
        this.riderId = riderId;
        this.status = status;
        this.updatedAt = Instant.now();
    }

    /**
     * Whether this user may watch this delivery.
     *
     * <p>Customer, merchant and assigned rider only. A rider who has not claimed the order cannot
     * see where another rider is, which matters because location is personal data about a worker.
     */
    public boolean isVisibleTo(String userId) {
        return customerId.equals(userId)
                || merchantId.equals(userId)
                || (riderId != null && riderId.equals(userId));
    }

    /** Tracking is only meaningful once someone has the food and before it is handed over. */
    public boolean isTrackable() {
        return "PICKED_UP".equals(status) || "READY".equals(status);
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public String getRiderId() {
        return riderId;
    }

    public String getStatus() {
        return status;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
