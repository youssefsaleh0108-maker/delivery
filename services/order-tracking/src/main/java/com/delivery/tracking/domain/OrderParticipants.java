package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import com.delivery.tracking.route.GeoPoint;

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

    /** The fleet carrying this order. Null for the platform's own riders, exactly as upstream. */
    @Column(name = "carrier_id")
    private UUID carrierId;

    @Column(name = "pickup_lat")
    private Double pickupLat;

    @Column(name = "pickup_lng")
    private Double pickupLng;

    @Column(name = "dropoff_lat")
    private Double dropoffLat;

    @Column(name = "dropoff_lng")
    private Double dropoffLng;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    /**
     * The statuses during which a rider's position is meaningful and may be watched.
     *
     * <p>{@code READY} is included because the rider is already on their way to the counter and the
     * customer's map should show that. Terminal statuses are not: once the food is handed over,
     * following the rider is following a person, not a delivery.
     */
    private static final Set<String> TRACKABLE_STATUSES = Set.of("READY", "PICKED_UP");

    /** Past this point the rider is carrying the goods, so the remaining leg is to the customer. */
    private static final String CARRYING_STATUS = "PICKED_UP";

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
     * Applies the parts of an order snapshot the ETA needs.
     *
     * <p>Every field is applied only when the event actually carries it. That is not defensive
     * padding: the publisher does not send coordinates at all yet, and a plain assignment would
     * mean the first {@code order.status_changed} after a route was learned wiped it out again and
     * the customer's ETA disappeared halfway through the delivery. Absent means "this event does
     * not say", never "this is now unknown".
     */
    public void applyRoute(UUID carrierId, GeoPoint pickup, GeoPoint dropoff) {
        boolean changed = false;
        if (carrierId != null && !carrierId.equals(this.carrierId)) {
            this.carrierId = carrierId;
            changed = true;
        }
        if (pickup != null) {
            this.pickupLat = pickup.lat();
            this.pickupLng = pickup.lng();
            changed = true;
        }
        if (dropoff != null) {
            this.dropoffLat = dropoff.lat();
            this.dropoffLng = dropoff.lng();
            changed = true;
        }
        if (changed) {
            this.updatedAt = Instant.now();
        }
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
        return TRACKABLE_STATUSES.contains(status);
    }

    /** The statuses {@link #isTrackable()} accepts, for queries that need the same definition. */
    public static Set<String> trackableStatuses() {
        return TRACKABLE_STATUSES;
    }

    /** True once the rider is carrying the goods, i.e. the remaining leg is to the customer. */
    public boolean isCarrying() {
        return CARRYING_STATUS.equals(status);
    }

    public UUID getCarrierId() {
        return carrierId;
    }

    /** Where the rider collects. Absent until the publisher carries coordinates — see V12. */
    public Optional<GeoPoint> pickup() {
        return GeoPoint.of(pickupLat, pickupLng);
    }

    /** Where the rider is going. Absent until the publisher carries coordinates — see V12. */
    public Optional<GeoPoint> dropoff() {
        return GeoPoint.of(dropoffLat, dropoffLng);
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
