package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * An order that was delivered, and may therefore be reviewed.
 *
 * <p>A projection off {@code order.delivered}, not a copy of the order. It carries the three facts a
 * review needs to be trustworthy — which order, whose it was, and which shop it came from — and
 * nothing else, because everything else would be a second version of state this service does not own.
 *
 * <p>Keyed on the order id so the projection is idempotent by construction: the bus is at-least-once,
 * and a redelivered {@code order.delivered} rewrites the same row rather than adding another.
 */
@Entity
@Table(name = "reviewable_orders")
public class ReviewableOrder {

    @Id
    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Column(name = "store_id", nullable = false)
    private UUID storeId;

    /** The customer's Keycloak {@code sub}. The only person entitled to rate this order. */
    @Column(name = "customer_id", nullable = false, length = 64)
    private String customerId;

    @Column(name = "delivered_at", nullable = false)
    private Instant deliveredAt;

    @Column(name = "recorded_at", nullable = false, insertable = false, updatable = false)
    private Instant recordedAt;

    protected ReviewableOrder() {
        // for JPA
    }

    public ReviewableOrder(UUID orderId, UUID storeId, String customerId, Instant deliveredAt) {
        this.orderId = orderId;
        this.storeId = storeId;
        this.customerId = customerId;
        this.deliveredAt = deliveredAt;
    }

    /**
     * Whether this customer may rate this shop for this order.
     *
     * <p>Both halves matter. Without the customer check anyone could rate anyone's order; without
     * the store check a customer could aim a genuine order's review at a shop they never bought
     * from — which is the more useful attack, because it needs no forged id at all.
     */
    public boolean allowsReviewBy(String candidateCustomerId, UUID candidateStoreId) {
        return customerId.equals(candidateCustomerId) && storeId.equals(candidateStoreId);
    }

    public UUID getOrderId() {
        return orderId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public Instant getDeliveredAt() {
        return deliveredAt;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }
}
