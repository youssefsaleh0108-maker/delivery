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

    /**
     * The checkout this order was placed in with other shops' orders; null when it was placed
     * alone. The whole of what links a multi-shop basket's orders — see V17.
     */
    @Column(name = "checkout_id")
    private UUID checkoutId;

    /** The shop's name as the order recorded it, which is what a checkout map's rows are called. */
    @Column(name = "store_name", length = STORE_NAME_LENGTH)
    private String storeName;

    /** When the rider collected: the occurredAt of the earliest PICKED_UP snapshot seen. */
    @Column(name = "picked_up_at")
    private Instant pickedUpAt;

    /** When the order was delivered or cancelled: the earliest terminal snapshot's occurredAt. */
    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    /** The column's width, which is also the product catalogue's limit on a shop's name. */
    private static final int STORE_NAME_LENGTH = 160;

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

    /** Nothing is arriving; the delivery is over one way or the other. */
    private static final Set<String> TERMINAL_STATUSES = Set.of("DELIVERED", "CANCELLED");

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

    /**
     * Applies a snapshot's rider and status, unless the order has already finished.
     *
     * <p>A delivered or cancelled order is finished for good. Delivery is at-least-once and not in
     * order, so a snapshot from before the end (a PICKED_UP redelivered after the DELIVERED, or
     * one that was simply slow) can land at any time. Applying it would reopen the order: the
     * rider's pings would be accepted again, it would count as a live delivery for the rider and
     * the customer, and a finished order's map would start following the rider again. The end is
     * recognised by a completion time or by a terminal status ({@link #isComplete()}), so an order
     * that finished before completed_at existed is held just as firmly.
     *
     * <p>The cost is that a PICKED_UP snapshot arriving only after the DELIVERED one no longer
     * stamps {@code picked_up_at}: the order is over, and nothing reads that time for a finished
     * order except as a label.
     */
    public void apply(String riderId, String status) {
        if (isComplete()) {
            return;
        }
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
     * Applies the checkout link and the shop's name, when the event carries them.
     *
     * <p>The same rule as {@link #applyRoute}: absent means "this event does not say", never "this
     * is now unknown". An order is linked to its checkout once, at placement, and nothing upstream
     * ever unlinks it, so there is no event whose silence should erase the link.
     *
     * <p>The name is cut to the column rather than refused. A message is untrusted input, and an
     * over-long name failing the insert would lose the whole event — the customer's right to watch
     * their own delivery included — over a label.
     */
    public void applyCheckout(UUID checkoutId, String storeName) {
        if (checkoutId != null) {
            this.checkoutId = checkoutId;
        }
        if (storeName != null && !storeName.isBlank()) {
            String name = storeName.strip();
            this.storeName = name.length() > STORE_NAME_LENGTH
                    ? name.substring(0, STORE_NAME_LENGTH)
                    : name;
        }
    }

    /**
     * Stamps when the order was collected and when it finished, from the snapshot just applied.
     *
     * <p>Earliest wins, rather than first-processed or last-processed. Delivery is at-least-once,
     * so the same PICKED_UP snapshot can arrive twice, and a later event still in PICKED_UP (a
     * reassigned fleet, a corrected address) carries a later occurredAt: either would move a stop
     * the rider really collected first to second place on the customer's map. The earliest instant
     * any PICKED_UP snapshot reports is the collection, whatever order the messages land in.
     *
     * <p>Judged on the status the snapshot itself reports, not on the status the order now holds:
     * a finished order keeps its terminal status whatever arrives later ({@link #apply}), and a
     * PICKED_UP replayed after the delivery must neither move the delivery's time nor be lost. A
     * collection is never stamped after the order finished.
     *
     * @param snapshotStatus the status the event reports, as it was applied or refused
     */
    public void stampMilestones(String snapshotStatus, Instant occurredAt) {
        if (occurredAt == null || snapshotStatus == null) {
            return;
        }
        if (CARRYING_STATUS.equals(snapshotStatus)
                && (completedAt == null || !occurredAt.isAfter(completedAt))
                && (pickedUpAt == null || occurredAt.isBefore(pickedUpAt))) {
            this.pickedUpAt = occurredAt;
        }
        if (TERMINAL_STATUSES.contains(snapshotStatus)
                && (completedAt == null || occurredAt.isBefore(completedAt))) {
            this.completedAt = occurredAt;
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

    /**
     * True once the delivery is over, delivered or cancelled.
     *
     * <p>The trail is closed at this point. Everything a rider's phone reports afterwards is the
     * rider's own movements, not the delivery's, and appending it would both extend a customer's
     * view of a worker past the job and grow the record a dispute is settled from after the fact.
     *
     * <p>Final: once a completion time is stamped the order stays complete, whatever a later
     * snapshot says (see {@link #apply}).
     */
    public boolean isComplete() {
        return completedAt != null || TERMINAL_STATUSES.contains(status);
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

    public UUID getCheckoutId() {
        return checkoutId;
    }

    public String getStoreName() {
        return storeName;
    }

    public Instant getPickedUpAt() {
        return pickedUpAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
