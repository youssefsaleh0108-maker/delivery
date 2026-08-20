package com.delivery.tracking.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One GPS ping from a rider.
 *
 * <p>The PostGIS {@code location} column is a generated column in the database and is deliberately
 * not mapped here — Postgres derives it from lat/lng, so the two can never disagree and the
 * application does not need hibernate-spatial on the classpath.
 */
@Entity
@Table(name = "tracking_events")
public class TrackingEvent {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Column(name = "rider_id", nullable = false, length = 64)
    private String riderId;

    @Column(name = "lat", nullable = false)
    private double lat;

    @Column(name = "lng", nullable = false)
    private double lng;

    /** GPS accuracy in metres, as reported by the device. Useful when a track looks implausible. */
    @Column(name = "accuracy_m")
    private Float accuracyM;

    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt;

    protected TrackingEvent() {
        // for JPA
    }

    public TrackingEvent(UUID orderId, String riderId, double lat, double lng, Float accuracyM) {
        this.id = UUID.randomUUID();
        this.orderId = orderId;
        this.riderId = riderId;
        this.lat = lat;
        this.lng = lng;
        this.accuracyM = accuracyM;
        this.recordedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public String getRiderId() {
        return riderId;
    }

    public double getLat() {
        return lat;
    }

    public double getLng() {
        return lng;
    }

    public Float getAccuracyM() {
        return accuracyM;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }
}
