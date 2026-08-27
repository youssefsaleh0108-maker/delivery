package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * One line of one delivered basket.
 *
 * <p>A projection off {@code order.delivered}, and the only record this service keeps of what was in
 * an order. It exists for exactly one question — "what else was in the baskets that contained this
 * product" — which is the only honest basis for a cross-sell rail in a service that cannot read the
 * orders schema.
 *
 * <p>It is not a copy of the order. There is no price here, no customer, no address and no status:
 * every one of those is state another service owns, and a second version of it here would be a
 * second version that drifts. What is here is the grouping key and the item, because that is what
 * counting baskets needs.
 *
 * <p>Keyed on {@code (orderId, productId)} so the projection is idempotent by construction. The bus
 * is at-least-once; a redelivered event must rewrite the basket it already wrote rather than count
 * it twice, and a surrogate id would make double-counting the default.
 */
@Entity
@Table(name = "delivered_order_lines")
@IdClass(DeliveredOrderLine.Key.class)
public class DeliveredOrderLine {

    @Id
    @Column(name = "order_id", nullable = false, updatable = false)
    private UUID orderId;

    @Id
    @Column(name = "product_id", nullable = false, updatable = false)
    private UUID productId;

    /**
     * Denormalised from the event so cross-sell can be scoped to one shop without joining products.
     *
     * <p>Also more durable than the join would be: a product that is later archived, or moved
     * between a merchant's stores, does not rewrite which shop this basket came from.
     */
    @Column(name = "store_id", nullable = false)
    private UUID storeId;

    @Column(name = "qty", nullable = false)
    private int qty;

    @Column(name = "delivered_at", nullable = false)
    private Instant deliveredAt;

    protected DeliveredOrderLine() {
        // for JPA
    }

    public DeliveredOrderLine(UUID orderId, UUID productId, UUID storeId, int qty,
                              Instant deliveredAt) {
        this.orderId = orderId;
        this.productId = productId;
        this.storeId = storeId;
        this.qty = qty;
        this.deliveredAt = deliveredAt;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public UUID getProductId() {
        return productId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public int getQty() {
        return qty;
    }

    public Instant getDeliveredAt() {
        return deliveredAt;
    }

    /** The composite key. Shape follows {@link StoreDeliveryZone.Key}. */
    public static class Key implements java.io.Serializable {

        private UUID orderId;
        private UUID productId;

        public Key() {
        }

        public Key(UUID orderId, UUID productId) {
            this.orderId = orderId;
            this.productId = productId;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return java.util.Objects.equals(orderId, key.orderId)
                    && java.util.Objects.equals(productId, key.productId);
        }

        @Override
        public int hashCode() {
            return java.util.Objects.hash(orderId, productId);
        }
    }
}
