package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * An area a customer picks from a list.
 *
 * <p>Not a polygon. Addresses in this market are landmarks and floor numbers, so the reliable way to
 * know where an order is going is to ask — which is what every local delivery app does. "Hamra" is a
 * better answer than a geocoder's best guess at "the building behind the pharmacy, third floor".
 *
 * <p>An area may carry a {@linkplain #centre() centre}: one point, roughly the middle of the
 * neighbourhood, placed by the back office (V30). It exists so the merchant demand map can draw the
 * area and so a shop's pin can find the areas around it. It is never a boundary, and pricing never
 * reads it.
 *
 * <p>Retired rather than deleted when a place stops being served: saved addresses reference it, and
 * removing the row would either orphan them or rewrite somebody's address without asking.
 */
@Entity
@Table(name = "delivery_zones")
public class DeliveryZone {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 120)
    private String name;

    /** Groups areas in the picker — "Beirut", "Mount Lebanon". */
    @Column(name = "region", length = 120)
    private String region;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder = 100;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    /**
     * Roughly the middle of the area. Both or neither, which {@link GeoPoint} enforces on the way in
     * and V30's CHECK stands behind. Null until the back office places the area.
     */
    @Column(name = "center_lat", precision = 9, scale = 6)
    private BigDecimal centerLat;

    @Column(name = "center_lng", precision = 9, scale = 6)
    private BigDecimal centerLng;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected DeliveryZone() {
        // for JPA
    }

    public DeliveryZone(String name, String region, int sortOrder) {
        this.id = UUID.randomUUID();
        this.name = name;
        this.region = region;
        this.sortOrder = sortOrder;
        this.active = true;
    }

    public void rename(String name, String region, int sortOrder) {
        this.name = name;
        this.region = region;
        this.sortOrder = sortOrder;
    }

    /**
     * Places the area on the map, or takes it off with {@code null}.
     *
     * <p>A {@link GeoPoint} rather than two loose numbers, so a half-entered centre, a value out of
     * range or the (0, 0) of an unset form field has already been refused before it gets here.
     */
    public void placeAt(GeoPoint centre) {
        this.centerLat = centre == null ? null : centre.latitude();
        this.centerLng = centre == null ? null : centre.longitude();
    }

    /** The area's centre, or null when it has not been placed. */
    public GeoPoint centre() {
        return GeoPoint.ofNullable(centerLat, centerLng);
    }

    public void retire() {
        this.active = false;
    }

    public void reinstate() {
        this.active = true;
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getRegion() {
        return region;
    }

    public int getSortOrder() {
        return sortOrder;
    }

    public boolean isActive() {
        return active;
    }

    public BigDecimal getCenterLat() {
        return centerLat;
    }

    public BigDecimal getCenterLng() {
        return centerLng;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
