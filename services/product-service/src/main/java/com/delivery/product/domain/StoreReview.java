package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One customer's rating of one order.
 *
 * <p>Anchored to an order rather than to a store: it is the only way to bound how often someone can
 * rate a shop, and it means a review is always attached to a purchase that actually happened. A
 * unique constraint on {@code order_id} enforces it in the database, because two taps racing would
 * both pass a read-then-write check in service code.
 */
@Entity
@Table(name = "store_reviews")
public class StoreReview {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Column(name = "customer_id", nullable = false, length = 64, updatable = false)
    private String customerId;

    /** Opaque across the service boundary — order-manager owns that table. */
    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Column(name = "rating", nullable = false)
    private short rating;

    @Column(name = "comment", columnDefinition = "text")
    private String comment;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected StoreReview() {
        // for JPA
    }

    public StoreReview(UUID storeId, String customerId, UUID orderId, int rating, String comment) {
        if (rating < 1 || rating > 5) {
            throw new IllegalArgumentException("A rating is between 1 and 5 stars");
        }
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.customerId = customerId;
        this.orderId = orderId;
        this.rating = (short) rating;
        this.comment = comment;
    }

    /** Lets a customer change their mind. The order it belongs to never moves. */
    public void revise(int rating, String comment) {
        if (rating < 1 || rating > 5) {
            throw new IllegalArgumentException("A rating is between 1 and 5 stars");
        }
        this.rating = (short) rating;
        this.comment = comment;
    }

    public boolean isBy(String candidate) {
        return customerId.equals(candidate);
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public short getRating() {
        return rating;
    }

    public String getComment() {
        return comment;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
