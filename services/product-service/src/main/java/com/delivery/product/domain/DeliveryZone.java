package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * An area a customer picks from a list.
 *
 * <p>Not a polygon and not a coordinate. Addresses in this market are landmarks and floor numbers,
 * so the reliable way to know where an order is going is to ask — which is what every local delivery
 * app does. "Hamra" is a better answer than a geocoder's best guess at "the building behind the
 * pharmacy, third floor".
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

    public Instant getCreatedAt() {
        return createdAt;
    }
}
